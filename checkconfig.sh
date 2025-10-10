echo --- ports ---
grep --include="*.conf" --exclude-dir=".*" -rniE "http_port|longpolling_port"
echo --- images ---
grep --include="*.txt" --exclude-dir=".*" -rniE ""
