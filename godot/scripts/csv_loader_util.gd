class_name CsvLoaderUtil
extends RefCounted

## FileAccess.get_csv_line() は eof_reached() が真になる直前、末尾に空行 [""] を
## もう1回返す（Godotの仕様）。これは著者のミスではないので警告対象から除く。
static func is_trailing_blank_row(row: PackedStringArray) -> bool:
	return row.size() == 1 and row[0] == ""
