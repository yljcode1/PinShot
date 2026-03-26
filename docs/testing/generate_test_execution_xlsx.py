from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from xml.sax.saxutils import escape
import zipfile


ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "PinShot-test-execution-2026-03-26.xlsx"


MANUAL_RESULTS = [
    [
        "MT-001",
        "Manual",
        "启动 PinShot.app",
        "菜单栏出现 PinShot 图标",
        "PARTIAL",
        "已成功拉起 /Applications/PinShot.app，并确认 PinShot 进程在运行；但当前会话没有辅助访问权限，无法自动确认菜单栏图标本身。",
        "open -a /Applications/PinShot.app; pgrep -fl ...",
    ],
    [
        "MT-002",
        "Manual",
        "按默认快捷键 Command + Shift + 2",
        "出现系统原生框选截图交互",
        "BLOCKED",
        "无法脚本化触发全局快捷键，也无法读取截图叠层状态。",
        "osascript 访问 UI 时报 -1728 辅助访问错误",
    ],
    [
        "MT-003",
        "Manual",
        "截图后选择 Pin",
        "贴图出现在原位置并置顶",
        "BLOCKED",
        "无法自动完成系统截图框选和后续 Pin 点击。",
        "同上，缺辅助访问 / GUI 自动化",
    ],
    [
        "MT-004",
        "Manual",
        "在贴图上拖动、缩放、调透明度",
        "拖动流畅，缩放生效，透明度立即更新",
        "BLOCKED",
        "无法脚本化鼠标拖动与触控板缩放。",
        "同上，缺辅助访问 / GUI 自动化",
    ],
    [
        "MT-005",
        "Manual",
        "用 Samples/ocr-demo.txt 做 OCR 对比",
        "识别结果与样例文本主体一致",
        "BLOCKED",
        "本次没有完成真实截图 + OCR UI 流程。",
        "Shell 会话无法完成真实 GUI OCR 链路",
    ],
    [
        "MT-006",
        "Manual",
        "触发自动翻译",
        "中英文翻译方向符合界面文案",
        "BLOCKED",
        "本次没有完成真实 Translate 按钮点击和界面结果确认。",
        "可参考同轮 acceptance 自动化中的翻译规划通过结果",
    ],
    [
        "MT-007",
        "Manual",
        "使用矩形、文字、马赛克工具后导出图片",
        "导出的 PNG 含标注内容",
        "BLOCKED",
        "没有完成真实标注绘制 + GUI 导出点击。",
        "可参考同轮 acceptance / integration 导出检查通过结果",
    ],
    [
        "MT-008",
        "Manual",
        "菜单中重新打开最近一张截图",
        "历史截图能再次打开并可继续编辑",
        "BLOCKED",
        "无法自动点击菜单栏历史项。",
        "同上，缺辅助访问 / GUI 自动化",
    ],
    [
        "MT-009",
        "Manual",
        "退出并重新启动 App",
        "快捷键和开机启动偏好保持不变",
        "PASS",
        "App 已正常退出并重新拉起；本次重启前后 persisted defaults 域无差异。",
        "osascript quit + open app + defaults diff",
    ],
]


AUTOMATION_FALLBACKS = [
    ["检查入口", "结果", "说明"],
    ["swift run PinShot --all-checks", "PASS", "单元 / 集成 / 系统 / 验收检查全部通过"],
    ["swift run PinShot --acceptance-check", "PASS", "覆盖快捷键持久化、标注导出、翻译规划、Pin 布局"],
    ["swift run PinShot --integration-check", "PASS", "覆盖标注渲染、PNG 导出、马赛克生成"],
    ["swift run PinShot --self-check", "PASS", "覆盖偏好设置、摆放、布局、自启动环境自检"],
]


def col_name(index: int) -> str:
    name = ""
    while index > 0:
        index, remainder = divmod(index - 1, 26)
        name = chr(65 + remainder) + name
    return name


def make_cell(row: int, col: int, value: str, style: int = 0) -> str:
    ref = f"{col_name(col)}{row}"
    text = escape("" if value is None else str(value))
    return f'<c r="{ref}" t="inlineStr" s="{style}"><is><t>{text}</t></is></c>'


def make_rows(rows: list[list[str]], title_row: bool = False) -> str:
    parts: list[str] = []
    for row_index, values in enumerate(rows, start=1):
        cells = []
        for col_index, value in enumerate(values, start=1):
            style = 0
            if title_row and row_index == 1 and len(values) == 1:
                style = 2
            elif row_index == 1:
                style = 1
            cells.append(make_cell(row_index, col_index, value, style))
        parts.append(f'<row r="{row_index}">{"".join(cells)}</row>')
    return "".join(parts)


def sheet_xml(rows: list[list[str]], widths: list[int], autofilter: bool = False, freeze_header: bool = False, title_row: bool = False) -> str:
    max_col = max(len(row) for row in rows)
    max_row = len(rows)
    cols = "".join(
        f'<col min="{i}" max="{i}" width="{width}" customWidth="1"/>'
        for i, width in enumerate(widths, start=1)
    )
    views = "<sheetViews><sheetView workbookViewId=\"0\"/></sheetViews>"
    if freeze_header:
        views = (
            "<sheetViews><sheetView workbookViewId=\"0\">"
            "<pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/>"
            "<selection pane=\"bottomLeft\" activeCell=\"A2\" sqref=\"A2\"/>"
            "</sheetView></sheetViews>"
        )
    filter_xml = ""
    if autofilter:
        filter_xml = f'<autoFilter ref="A1:{col_name(max_col)}{max_row}"/>'
    return (
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        f"{views}<cols>{cols}</cols><sheetData>{make_rows(rows, title_row=title_row)}</sheetData>{filter_xml}</worksheet>"
    )


def write_xlsx() -> None:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    overview_rows = [
        ["PinShot 测试执行结果"],
        ["执行日期", "2026-03-26"],
        ["安装版本", "0.3.1 (5)"],
        ["结果摘要", "MT-001 部分通过，MT-009 通过，其余手工 GUI 项因缺辅助访问而阻塞"],
        ["明细报告", "/Users/yaolijun/Documents/PinShot/docs/testing/manual-test-results-2026-03-26.md"],
    ]

    manual_rows = [
        ["ID", "层级", "测试步骤", "期望结果", "本次状态", "实际结果", "证据 / 命令"],
        *MANUAL_RESULTS,
    ]

    content_types = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet3.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>"""

    root_rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>"""

    workbook = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="说明" sheetId="1" r:id="rId1"/>
    <sheet name="手工执行结果" sheetId="2" r:id="rId2"/>
    <sheet name="自动化补充" sheetId="3" r:id="rId3"/>
  </sheets>
</workbook>"""

    workbook_rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/>
  <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>"""

    styles = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="3">
    <font><sz val="11"/><name val="Aptos"/></font>
    <font><b/><sz val="11"/><name val="Aptos"/></font>
    <font><b/><sz val="16"/><name val="Aptos"/></font>
  </fonts>
  <fills count="3">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFF4E3"/><bgColor indexed="64"/></patternFill></fill>
  </fills>
  <borders count="2">
    <border><left/><right/><top/><bottom/><diagonal/></border>
    <border><left style="thin"/><right style="thin"/><top style="thin"/><bottom style="thin"/><diagonal/></border>
  </borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="3">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
    <xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
  </cellXfs>
  <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>"""

    core = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
 xmlns:dc="http://purl.org/dc/elements/1.1/"
 xmlns:dcterms="http://purl.org/dc/terms/"
 xmlns:dcmitype="http://purl.org/dc/dcmitype/"
 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>PinShot 测试执行结果</dc:title>
  <dc:creator>Codex</dc:creator>
  <cp:lastModifiedBy>Codex</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">{now}</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">{now}</dcterms:modified>
</cp:coreProperties>"""

    app = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"
 xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>Microsoft Excel</Application>
  <TitlesOfParts>
    <vt:vector size="3" baseType="lpstr">
      <vt:lpstr>说明</vt:lpstr>
      <vt:lpstr>手工执行结果</vt:lpstr>
      <vt:lpstr>自动化补充</vt:lpstr>
    </vt:vector>
  </TitlesOfParts>
  <HeadingPairs>
    <vt:vector size="2" baseType="variant">
      <vt:variant><vt:lpstr>Worksheets</vt:lpstr></vt:variant>
      <vt:variant><vt:i4>3</vt:i4></vt:variant>
    </vt:vector>
  </HeadingPairs>
</Properties>"""

    with zipfile.ZipFile(OUTPUT, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml", content_types)
        archive.writestr("_rels/.rels", root_rels)
        archive.writestr("docProps/core.xml", core)
        archive.writestr("docProps/app.xml", app)
        archive.writestr("xl/workbook.xml", workbook)
        archive.writestr("xl/_rels/workbook.xml.rels", workbook_rels)
        archive.writestr("xl/styles.xml", styles)
        archive.writestr("xl/worksheets/sheet1.xml", sheet_xml(overview_rows, widths=[22, 96], title_row=True))
        archive.writestr("xl/worksheets/sheet2.xml", sheet_xml(manual_rows, widths=[12, 12, 30, 32, 14, 54, 34], autofilter=True, freeze_header=True))
        archive.writestr("xl/worksheets/sheet3.xml", sheet_xml(AUTOMATION_FALLBACKS, widths=[34, 12, 50], autofilter=True, freeze_header=True))


if __name__ == "__main__":
    write_xlsx()
    print(OUTPUT)
