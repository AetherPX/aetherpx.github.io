#!/system/bin/sh

# ==================== 初始化 ====================
# 工程名
project=$(cat "$TMPDIR/DNA.ini" 2>/dev/null) || {
    echo "错误: 无法读取 DNA.ini" >&2
    exit 1
}

# 内部储存工程目录
DNA_PRO="$DNA_DIR/$project"
# 外部工程目录
DNA_TMP="$DNA_TMP/$project"
# img信息目录
configdir="$DNA_TMP/config"
# 插件工具存放目录
subbin="$START_DIR/module/super/bin"

# 定义移植相关参数及路径
PORT_DEVICE="nezha"
FW_DEVICE="marble"
mi_ext_prop="$DNA_TMP/mi_ext/etc/build.prop"
product_prop="$DNA_TMP/product/etc/build.prop"
system_prop="$DNA_TMP/system/system/build.prop"
vendor_prop="$DNA_TMP/vendor/build.prop"
odm_prop="$DNA_TMP/odm/etc/build.prop"

# 需要复制的分区
sources=(
    "$DNA_TMP/../note12tbFiles/product/"
    # "$DNA_TMP/../note12tbFiles/system/"
    "$DNA_TMP/../note12tbFiles/system_ext/"
)
destinations=(
    "$DNA_TMP/product/"
    # "$DNA_TMP/system/"
    "$DNA_TMP/system_ext/"
)

cd "$DNA_TMP" || exit 1

# ==================== 打印函数 ====================
print_msg() { echo "$*"; }
print_error() { echo "✗错误: $1" >&2; }
print_success() { echo "✓成功: $1"; }
print_warning() { echo "⚠: $1"; }
print_info() { echo "ⓘ $1"; }
print_title() { echo "$1"; }

# ==================== 通用辅助函数 ====================
# 安全追加 prop（若不存在）
add_prop_if_not_exist() {
    local file="$1" pattern="$2" line="$3"
    if [ -f "$file" ]; then
        if ! grep -qF "$pattern" "$file"; then
            echo "$line" >> "$file"
            print_success "已添加: $line"
            return 0
        else
            print_info "已存在: $pattern"
            return 1
        fi
    else
        print_error "文件不存在: $file"
        return 2
    fi
}

# 安全替换文件中的字符串
replace_in_file() {
    local file="$1" from="$2" to="$3"
    if [ -f "$file" ]; then
        if grep -q "$from" "$file"; then
            sed -i "s/$from/$to/g" "$file"
            print_success "已修改: $file ($from → $to)"
            return 0
        else
            print_error " $file 中未匹配到: $from"
            return 1
        fi
    else
        print_error "文件不存在: $file"
        return 2
    fi
}

# 安全删除目录（检查存在性）
safe_rm_dir() {
    local dir="$1"
    if [ -d "$dir" ]; then
        rm -rf "$dir"
        print_success "已删除: $dir"
    else
        print_warning "目录不存在: $dir"
    fi
}

# ==================== 主流程 ====================
print_title "===== 开始移植处理 ====="

# 处理 odm 配置
print_title "1. 处理 odm&vendor 配置"
if [ -d "$DNA_TMP/odm/" ]; then
    if [ -f "$odm_prop" ]; then
        if ! grep -q "sys.haptic.runin=2" "$odm_prop"; then
            cat <<EOF >> "$odm_prop"
sys.haptic.down.weak=2
sys.haptic.down.normal=2
sys.haptic.down.strong=2
sys.haptic.down=2,2
sys.haptic.tap.normal=2,2
sys.haptic.tap.light=2,2
sys.haptic.flick=2,2
sys.haptic.flick.light=2,2
sys.haptic.switch=2,2
sys.haptic.mesh.heavy=2,2
sys.haptic.mesh.normal=2,2
sys.haptic.mesh.light=2,2
sys.haptic.long.press=2,2
sys.haptic.popup.normal=2,2
sys.haptic.popup.light=2,2
sys.haptic.pickup=2,2
sys.haptic.scroll.edge=2,2
sys.haptic.trigger.drawer=2,2
sys.haptic.hold=2,2
sys.haptic.runin=2
EOF
            print_success "odm 配置已追加"
        else
            print_info "odm 配置已存在"
        fi
    else
        print_error "odm 配置文件不存在: $odm_prop"
    fi
else
    print_warning "未找到 odm 目录"
fi

# 处理 vendor 配置
vendor_processed=0
if [ -d "$DNA_TMP/vendor/" ]; then
    source_vendor="$DNA_TMP/../note12tbFiles/vendor/"
    if [ -d "$source_vendor" ]; then
        cp -rf "$source_vendor"/* "$DNA_TMP/vendor/" 2>/dev/null
        [ $? -eq 0 ] && print_success "vendor 文件复制完成" && ((vendor_processed++))
    else
        print_warning "未找到源 vendor 目录: $source_vendor"
    fi

    # 修改 Dolby 配置
    dolby_config="$DNA_TMP/vendor/etc/dolby/dax-default.xml"
    if [ -f "$dolby_config" ] && grep -q '<volume-leveler-enable value="true"/>' "$dolby_config"; then
        sed -i 's/<volume-leveler-enable value="true"\/>/<volume-leveler-enable value="false"\/>/g' "$dolby_config"
        print_success "Dolby 配置已修改"
        ((vendor_processed++))
    fi

    # 修改 NFC 配置
    if [ -f "$vendor_prop" ]; then
        if grep -q "ro.vendor.nfc.dispatch_optim=1" "$vendor_prop"; then
            replace_in_file "$vendor_prop" "ro.vendor.nfc.dispatch_optim=1" "ro.vendor.nfc.dispatch_optim=2"
            ((vendor_processed++))
        elif grep -q "ro.vendor.nfc.wallet_fusion=1" "$vendor_prop"; then
            print_info "NFC 配置已存在，无需修改"
        else
            print_info "未找到原 NFC 配置"
        fi
    else
        print_error "vendor 配置文件不存在: $vendor_prop"
    fi

    [ $vendor_processed -gt 0 ] && print_success "vendor 配置处理完成 ($vendor_processed 项操作)"
else
    print_warning "未找到 vendor 目录"
fi

# 处理 build.prop 文件
echo
print_title "2. 处理 build.prop 文件"
# mi_ext 导入 atp.prop
if [ -f "$mi_ext_prop" ]; then
    if ! grep -qF 'import /product/etc/atp.prop' "$mi_ext_prop"; then
        sed -i "1iimport /product/etc/atp.prop" "$mi_ext_prop"
        print_success "已导入 atp.prop"
    else
        print_info "atp.prop 已导入"
    fi
else
    print_error "mi_ext build.prop 不存在"
fi

# prop机型代号修改
echo
print_title "3. 修改prop内机型代号"

replace_in_file "$mi_ext_prop" "$PORT_DEVICE" "$FW_DEVICE"

replace_in_file "$product_prop" "$PORT_DEVICE" "$FW_DEVICE"

# 精简操作
echo
print_title "4. 执行精简操作"
targets=(
    "$DNA_TMP/product/priv-app/MiniGameService"
    "$DNA_TMP/product/priv-app/MIUIBrowser"
    "$DNA_TMP/product/priv-app/Bdsms"
    "$DNA_TMP/product/data-app/BaiduIME"
    "$DNA_TMP/product/data-app/iFlytekIME"
    "$DNA_TMP/product/data-app/MIGalleryLockscreen"
    "$DNA_TMP/product/data-app/MIService"
    "$DNA_TMP/product/data-app/MIUIEmail"
    "$DNA_TMP/product/data-app/MIUIHuanji"
    "$DNA_TMP/product/data-app/MIUIMiDrive"
    "$DNA_TMP/product/data-app/MIUIVirtualSim"
    "$DNA_TMP/product/data-app/MiShop"
    "$DNA_TMP/product/data-app/MIpay"
    "$DNA_TMP/product/data-app/MIUIDuokanReader"
    "$DNA_TMP/product/data-app/MIUIGameCenter"
    "$DNA_TMP/product/data-app/MIUIMusicT"
    "$DNA_TMP/product/data-app/MIUINewHome_Removable"
    "$DNA_TMP/product/data-app/MIUIVideo"
    "$DNA_TMP/product/data-app/MIUIYoupin"
    "$DNA_TMP/product/app/HybridPlatform"
    "$DNA_TMP/product/app/MSA"
    "$DNA_TMP/product/app/AnalyticsCore"
    "$DNA_TMP/product/app/Updater"
    "$DNA_TMP/product/app/MiTrustService"
    "$DNA_TMP/product/app/MiBugReportOS3/"
    "$DNA_TMP/product/app/subscreencenter/"
    "$DNA_TMP/product/app/BSGameCenter/"
    "$DNA_TMP/product/app/MiAONServiceW/"
    "$DNA_TMP/product/app/XiaomiSimActivateServiceCn/"
)

deleted_count=0
not_found_count=0
for target in "${targets[@]}"; do
    if [ -d "$target" ]; then
        rm -rf "$target"
        ((deleted_count++))
    else
        ((not_found_count++))
    fi
done

# 删除单个 apk 文件
[ -f "$DNA_TMP/product/overlay/NfcResCommon_Sys.apk" ] && rm -f "$DNA_TMP/product/overlay/NfcResCommon_Sys.apk"

# 删除所有 nfc 相关目录
find "$DNA_TMP/product/pangu/system/app" -type d -iname "*nfc*" -exec rm -rf {} + 2>/dev/null

print_info "精简完成: 删除 $deleted_count 个目录"
print_warning "未找到 $not_found_count 个目录"

# 复制分区文件
echo
print_title "5. 处理分区文件"
copied_count=0
for i in "${!sources[@]}"; do
    src="${sources[$i]}"
    dest="${destinations[$i]}"
    if [ -d "$src" ]; then
        cp -rf "$src"* "$dest" 2>/dev/null
        if [ $? -eq 0 ]; then
            print_success "复制成功: $src → $dest"
            ((copied_count++))
        else
            print_error "复制失败: $src → $dest"
        fi
    else
        print_warning "源目录不存在: $src"
    fi
done
print_info "复制完成: 成功 $copied_count 个分区"

# 禁用 tango 转译器
echo
print_title "6. 禁用 tango 转译器"
if [ -f "$system_prop" ]; then
    sed -i '/^[^#]*tango/ s/^/#/' "$system_prop"
    print_success "已禁用 tango 转译器"
else
    print_error "system build.prop 不存在"
fi

echo
print_title "所有操作已完成"
print_info "记得去反编译设置"
print_info "记得去反编译系统界面组件"

exit 0