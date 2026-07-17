class_name NumberFormat

## 表示用の数値整形（ロジックなし・Node非依存でユニットテスト対象）。
## FINISH回数が数百万〜兆に伸びても読めるようにする。

## 3桁カンマ区切り。例: 1234567 -> "1,234,567"
static func group(value: int) -> String:
	var sign := "-" if value < 0 else ""
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return sign + out

## 万・億・兆の単位で短く表す（レート表示用）。例: 123456.0 -> "12.3万"
static func ja_unit(value: float) -> String:
	if value >= 1.0e12:
		return _trim("%.1f" % (value / 1.0e12)) + "兆"
	if value >= 1.0e8:
		return _trim("%.1f" % (value / 1.0e8)) + "億"
	if value >= 1.0e4:
		return _trim("%.1f" % (value / 1.0e4)) + "万"
	if value >= 10.0:
		return str(int(round(value)))
	return _trim("%.1f" % value)

static func _trim(text: String) -> String:
	return text.trim_suffix(".0")
