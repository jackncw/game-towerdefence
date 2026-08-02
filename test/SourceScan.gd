extends RefCounted
class_name SourceScan
## 掃原始碼嘅共用機件:行勻一個目錄,逐行交返**剝走註解之後**嘅程式碼。
##
## 點解要掃原始碼:有啲不變式冇一個執行時嘅問法。
##   * 「冇一句程式碼仲用緊 5x」(SpeedScaleTest)—— 5x 唔存在,所以冇嘢
##     可以觀察佢。
##   * 「出貨版冇路去開發畫面」(FlowTest)—— 一粒接住 lambda 嘅掣,由外面
##     問唔到佢通去邊,而真係撳落去就會離開個測試場景。
## 兩條都係關於**source 入面有冇呢句嘢**,所以兩條都用呢度。
##
## 剝走註解係關鍵:呢個 codebase 嘅價值有一半喺註解入面,而一條連解釋都
## 禁埋嘅規則會逼人刪走理由。「唔准寫」同「唔准做」係兩件事。

## 剝走 `#` 註解,但唔可以斬斷字串入面嘅 `#`(顏色碼 "#1c1611" 就係一個)。
static func strip_comment(line: String) -> String:
	var quote := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if quote != "":
			if c == "\\":
				i += 2
				continue
			if c == quote:
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
		elif c == "#":
			return line.substr(0, i)
		i += 1
	return line

## 行勻 `dirs` 底下每一個 .gd,交返 [{file, line_no, code}]。
## `skip_files` 係檔名(唔係路徑),用嚟豁免規則自己嗰個定義檔。
static func code_lines(dirs: Array, skip_files: Array = []) -> Array:
	var out: Array = []
	for d in dirs:
		_walk(String(d), skip_files, out)
	return out

static func _walk(path: String, skip_files: Array, out: Array) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := path + "/" + name
		if d.current_is_dir():
			if not name.begins_with("."):
				_walk(full, skip_files, out)
		elif name.ends_with(".gd") and not (name in skip_files):
			_read(full, out)
		name = d.get_next()
	d.list_dir_end()

static func _read(path: String, out: Array) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var n := 0
	while not f.eof_reached():
		n += 1
		var code := strip_comment(f.get_line())
		if code.strip_edges() == "":
			continue
		out.append({"file": path, "line_no": n, "code": code})
	f.close()
