from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from xml.sax.saxutils import escape
import zipfile


ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "PinShot-test-cases.xlsx"


AUTOMATED_CASES = [
    ["UT-001", "Unit", "偏好设置", "开机自启动默认值", "--unit-check", "launchAtLoginEnabled == true", ""],
    ["UT-002", "Unit", "偏好设置", "快捷键配置持久化", "--unit-check", "保存后读取结果一致", ""],
    ["UT-003", "Unit", "偏好设置", "非法快捷键配置回退", "--unit-check", "读取结果回退到默认快捷键", ""],
    ["UT-004", "Unit", "OCR 展示", "OCR 历史标题裁剪", "--unit-check", "标题去除首尾空白并截取前缀", ""],
    ["UT-005", "Unit", "OCR 展示", "OCR 占位文本回退标题", "--unit-check", "标题回退为 Capture <time>", ""],
    ["UT-006", "Unit", "截图摆放", "截图初始摆放边界", "--unit-check", "截图矩形被限制在可视区域内", "本轮顺手修复了该边界问题"],
    ["UT-007", "Unit", "操作面板", "操作面板底部翻转", "--unit-check", "靠近底边时面板显示到锚点下方", ""],
    ["UT-008", "Unit", "Pin 布局", "Pin 面板尺寸约束", "--unit-check", "编辑态尺寸仍位于可视区内", ""],
    ["UT-009", "Unit", "快捷键", "修饰键 Carbon 映射", "--unit-check", "command/shift/option/control 全部保留", ""],
    ["UT-010", "Unit", "快捷键", "快捷键展示文案顺序", "--unit-check", "修饰键顺序稳定", ""],
    ["UT-011", "Unit", "快捷键", "未知按键展示兜底", "--unit-check", "返回 KeyCode <n>", ""],
    ["UT-012", "Unit", "翻译规划", "无效 OCR 文本不生成翻译计划", "--unit-check", "返回 nil", ""],
    ["UT-013", "Unit", "翻译规划", "英文翻译方向", "--unit-check", "规划为 English -> Chinese (Simplified)", ""],
    ["UT-014", "Unit", "翻译规划", "中文翻译方向", "--unit-check", "规划为 Chinese (Simplified) -> English", ""],
    ["IT-001", "Integration", "渲染导出", "标注渲染 PNG 导出", "--integration-check", "可生成非空 PNG 数据", ""],
    ["IT-002", "Integration", "渲染导出", "标注导出内容发生变化", "--integration-check", "导出 PNG 与原始图片数据不同", ""],
    ["IT-003", "Integration", "渲染导出", "马赛克渲染", "--integration-check", "可对归一化区域生成有效 CGImage", ""],
    ["ST-001", "System", "自检", "偏好设置自检", "--self-check", "默认值与快捷键读写通过", ""],
    ["ST-002", "System", "自检", "截图标题与摆放自检", "--self-check", "标题、Chooser、摆放逻辑通过", ""],
    ["ST-003", "System", "自检", "Pin 面板布局自检", "--self-check", "普通态与编辑态布局通过", ""],
    ["ST-004", "System", "自检", "开机自启动环境自检", "--self-check", "isSupported 与运行环境状态一致", ""],
    ["AT-001", "Acceptance", "用户工作流", "快捷键设置工作流", "--acceptance-check", "业务偏好可按用户动作保存并恢复", ""],
    ["AT-002", "Acceptance", "用户工作流", "标注后导出工作流", "--acceptance-check", "标注图可渲染、导出、写盘并回读", ""],
    ["AT-003", "Acceptance", "用户工作流", "OCR 翻译规划工作流", "--acceptance-check", "中英文识别后翻译方向符合产品预期", ""],
    ["AT-004", "Acceptance", "用户工作流", "Pin 编辑面板布局工作流", "--acceptance-check", "编辑态尺寸在屏幕内且保留工具区空间", ""],
]


MANUAL_CASES = [
    ["MT-001", "Manual", "启动 PinShot.app", "菜单栏出现 PinShot 图标", "需要 GUI 环境"],
    ["MT-002", "Manual", "按默认快捷键 Command + Shift + 2", "出现系统原生框选截图交互", "需要屏幕录制权限"],
    ["MT-003", "Manual", "截图后选择 Pin", "贴图出现在原位置并置顶", ""],
    ["MT-004", "Manual", "在贴图上拖动、缩放、调透明度", "拖动流畅，缩放生效，透明度立即更新", ""],
    ["MT-005", "Manual", "用 Samples/ocr-demo.txt 做 OCR 对比", "识别结果与样例文本主体一致", "样例文件在 Samples 目录"],
    ["MT-006", "Manual", "触发自动翻译", "中英文翻译方向符合界面文案", ""],
    ["MT-007", "Manual", "使用矩形、文字、马赛克工具后导出图片", "导出的 PNG 含标注内容", ""],
    ["MT-008", "Manual", "菜单中重新打开最近一张截图", "历史截图能再次打开并可继续编辑", ""],
    ["MT-009", "Manual", "退出并重新启动 App", "快捷键和开机启动偏好保持不变", ""],
]


COMMANDS = [
    ["命令", "说明"],
    ["swift run PinShot --unit-check", "运行单元检查"],
    ["swift run PinShot --integration-check", "运行集成检查"],
    ["swift run PinShot --self-check", "运行系统自检"],
    ["swift run PinShot --acceptance-check", "运行验收检查"],
    ["swift run PinShot --all-checks", "一次跑完全部检查"],
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


def make_rows(rows: list[list[str]], header: bool = True) -> str:
    parts: list[str] = []
    for row_index, values in enumerate(rows, start=1):
        cells = []
        style = 1 if header and row_index == 1 else 0
        for col_index, value in enumerate(values, start=1):
            cell_style = style
            if row_index == 1 and col_index == 1 and values[0].startswith("PinShot"):
                cell_style = 2
            cells.append(make_cell(row_index, col_index, value, cell_style))
        parts.append(f'<row r="{row_index}">{"".join(cells)}</row>')
    return "".join(parts)


def sheet_xml(rows: list[list[str]], widths: list[int], autofilter: bool = False, freeze_header: bool = False) -> str:
    max_col = max(len(row) for row in rows)
    max_row = len(rows)
    cols = "".join(
        f'<col min="{i}" max="{i}" width="{width}" customWidth="1"/>'
        for i, width in enumerate(widths, start=1)
    )
    pane = ""
    views = "<sheetViews><sheetView workbookViewId=\"0\"/></sheetViews>"
    if freeze_header:
        pane = (
            "<sheetViews><sheetView workbookViewId=\"0\">"
            "<pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/>"
            "<selection pane=\"bottomLeft\" activeCell=\"A2\" sqref=\"A2\"/>"
            "</sheetView></sheetViews>"
        )
        views = pane
    filter_xml = ""
    if autofilter:
        filter_xml = f'<autoFilter ref="A1:{col_name(max_col)}{max_row}"/>'
    return (
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        f"{views}"
        f"<cols>{cols}</cols>"
        f"<sheetData>{make_rows(rows)}</sheetData>"
        f"{filter_xml}"
        "</worksheet>"
    )


def write_xlsx() -> None:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    overview_rows = [
        ["PinShot 测试用例总表"],
        ["版本", "0.3.2"],
        ["更新日期", "2026-03-26"],
        ["工作区", "/Users/yaolijun/Documents/PinShot"],
        ["说明", "这个文件可直接用 Excel 或 Numbers 打开"],
        [],
        *COMMANDS,
    ]

    automated_rows = [
        ["ID", "层级", "模块", "检查点", "执行入口", "期望结果", "备注"],
        *AUTOMATED_CASES,
    ]

    manual_rows = [
        ["ID", "层级", "操作步骤", "期望结果", "备注"],
        *MANUAL_CASES,
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
    <sheet name="自动化用例" sheetId="2" r:id="rId2"/>
    <sheet name="手工回归" sheetId="3" r:id="rId3"/>
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
    <fill><patternFill patternType="solid"><fgColor rgb="FFD9EAF7"/><bgColor indexed="64"/></patternFill></fill>
  </fills>
  <borders count="2">
    <border><left/><right/><top/><bottom/><diagonal/></border>
    <border>
      <left style="thin"/><right style="thin"/><top style="thin"/><bottom style="thin"/><diagonal/>
    </border>
  </borders>
  <cellStyleXfs count="1">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
  </cellStyleXfs>
  <cellXfs count="3">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">
      <alignment horizontal="center" vertical="center" wrapText="1"/>
    </xf>
    <xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
  </cellXfs>
  <cellStyles count="1">
    <cellStyle name="Normal" xfId="0" builtinId="0"/>
  </cellStyles>
</styleSheet>"""

    core = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
 xmlns:dc="http://purl.org/dc/elements/1.1/"
 xmlns:dcterms="http://purl.org/dc/terms/"
 xmlns:dcmitype="http://purl.org/dc/dcmitype/"
 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>PinShot 测试用例</dc:title>
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
      <vt:lpstr>自动化用例</vt:lpstr>
      <vt:lpstr>手工回归</vt:lpstr>
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
        archive.writestr(
            "xl/worksheets/sheet1.xml",
            sheet_xml(overview_rows, widths=[24, 48], freeze_header=False, autofilter=False),
        )
        archive.writestr(
            "xl/worksheets/sheet2.xml",
            sheet_xml(automated_rows, widths=[12, 14, 18, 28, 22, 40, 24], freeze_header=True, autofilter=True),
        )
        archive.writestr(
            "xl/worksheets/sheet3.xml",
            sheet_xml(manual_rows, widths=[12, 14, 40, 38, 20], freeze_header=True, autofilter=True),
        )


if __name__ == "__main__":
    write_xlsx()
    print(OUTPUT)
