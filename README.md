# CMD Python Launchers (Windows)

ชุดไฟล์ launcher `.cmd` สำหรับโปรเจกต์ Python บน Windows แยกเป็น 2 แบบ:

- `normal/run.cmd`: สำหรับโปรเจกต์ Python ทั่วไป (`requirements.txt` + optional `.venv`)
- `uv/run.cmd`: สำหรับโปรเจกต์ uv (`pyproject.toml`) flow สั้น `uv sync` + `uv run`

## โครงสร้าง

```text
cmd-python-launcher/
	normal/
		run.cmd
	uv/
		run.cmd
	tests/
		run_cmd_logic_tests.ps1
	README.md
```

## 1) Launcher สำหรับ Python ปกติ

ไฟล์: `normal/run.cmd`

### Flow หลัก

1. ใช้ `.venv` ก่อน (ถ้ามีและ Python เวอร์ชันผ่าน)
2. เช็ค requirements ใน `.venv`
3. ถ้า `.venv` ไม่พร้อม ให้ลอง system Python
4. ถ้า Python ต่ำกว่า minimum จะ fallback ไปสร้าง `.venv` ด้วย `uv` หรือ Python ปกติ
5. ถ้าไม่มี Python เลย จะ fallback ไป `uv run`
6. มี cache (`.run-cache.json`) เพื่อลดการเช็คซ้ำ

### Config ที่แก้บ่อย (อยู่บนสุดของไฟล์)

- `CFG_ENTRY_SCRIPT=main.py`
- `CFG_REQUIREMENTS_FILE=requirements.txt`
- `CFG_VENV_DIR=.venv`
- `CFG_CACHE_FILE=.run-cache.json`
- `CFG_MIN_PY=3.7`
- `CFG_PREFERRED_UV_PYTHON=3.11`
- `CFG_ENABLE_CACHE=1`
- `CFG_AUTO_INSTALL_UV=1`

### ตัวอย่างใช้งาน

```bat
run.cmd
run.cmd --help
run.cmd -m some_arg
```

## 2) Launcher สำหรับ uv project

ไฟล์: `uv/run.cmd`

### Flow หลัก

1. เช็คว่ามี `uv` ไหม
2. ถ้าไม่มี และเปิด auto install ไว้ จะติดตั้งด้วย official installer
3. รัน `uv sync`
4. รัน `uv run <target> <args>`

### Config ที่แก้บ่อย

- `CFG_RUN_TARGET=main.py`
- `CFG_SYNC_ARGS=`
- `CFG_AUTO_INSTALL_UV=1`

### ตัวอย่างใช้งาน

```bat
run.cmd
run.cmd --help
```

## การทดสอบ launcher แบบ Python ปกติ

ไฟล์เทส: `tests/run_cmd_logic_tests.ps1`

สิ่งที่เทสครอบคลุม:

- Existing `.venv` + requirements ผ่าน
- Cache hit
- Existing `.venv` แต่ requirements ต่าง
- System Python direct run
- Low Python + uv exists
- Low Python + uv missing
- No Python + uv fallback
- No Python + no uv (installer branch invocation)

คำสั่งรันเทส:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run_cmd_logic_tests.ps1
```

หมายเหตุ: เทสจะสร้างโฟลเดอร์ชั่วคราวที่ `tests/.sandbox` และเขียนผล `results.json` ภายในนั้น

## หมายเหตุสำคัญ

- ใช้กับ Windows (`.cmd`) โดยตรง
- ตัวติดตั้ง [uv](https://github.com/astral-sh/uv) ที่ใช้:

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

- ถ้าพึ่งติดตั้ง uv ใหม่ อาจต้องเปิด terminal ใหม่เพื่อให้ PATH อัปเดต
