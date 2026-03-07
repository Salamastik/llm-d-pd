# Generate a Hebrew CV PDF using reportlab (platypus)
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.units import cm
import os

# Try to locate a Hebrew-supporting font (DejaVuSans commonly available)
font_path_candidates = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"
]

font_path = None
for p in font_path_candidates:
    if os.path.exists(p):
        font_path = p
        break

font_name = "Helvetica"
if font_path:
    pdfmetrics.registerFont(TTFont("CustomFont", font_path))
    font_name = "CustomFont"

styles = getSampleStyleSheet()

title = ParagraphStyle(
    "Title",
    parent=styles["Heading1"],
    fontName=font_name,
    fontSize=22,
    leading=26,
    alignment=1
)

heading = ParagraphStyle(
    "Heading",
    parent=styles["Heading2"],
    fontName=font_name,
    fontSize=16,
    leading=20
)

text = ParagraphStyle(
    "Text",
    parent=styles["BodyText"],
    fontName=font_name,
    fontSize=11,
    leading=16
)

file_path = "./lscv_ai_infrastructure_hebrew.pdf"

elements = []

elements.append(Paragraph("קורות חיים – מהנדס תשתיות AI / MLOps", title))
elements.append(Spacer(1,20))

contact_data = [
    ["שם:", "השם שלך"],
    ["טלפון:", "050-0000000"],
    ["אימייל:", "email@example.com"],
    ["LinkedIn:", "linkedin.com/in/yourname"],
    ["GitHub:", "github.com/yourname"],
    ["מיקום:", "ישראל"]
]

table = Table(contact_data, colWidths=[4*cm, 12*cm])
elements.append(table)
elements.append(Spacer(1,20))

elements.append(Paragraph("תקציר מקצועי", heading))
elements.append(Paragraph(
    "מהנדס תשתיות AI ו-MLOps עם ניסיון בבנייה והפעלה של פלטפורמות למידת מכונה ו-LLM בקנה מידה גדול. "
    "ניסיון בפריסת מודלים על Kubernetes ו-OpenShift עם תשתיות GPU, בניית סביבת עבודה למדעני נתונים "
    "באמצעות JupyterHub, ופיתוח כלי SDK ו-CLI המייעלים תהליכי עבודה של צוותי ML.", text))
elements.append(Spacer(1,16))

elements.append(Paragraph("מיומנויות טכנולוגיות", heading))
skills = [
"LLM Deployment ו-Model Serving",
"Kubernetes ו-OpenShift",
"תשתיות GPU ועומסי עבודה של AI",
"JupyterHub וסביבות עבודה למדעני נתונים",
"Python ו-Bash",
"פיתוח SDK ו-CLI לפלטפורמות ML",
"CI/CD למודלים של Machine Learning",
"Docker, Helm ו-Git",
"Monitoring ו-Logging למערכות AI"
]

for s in skills:
    elements.append(Paragraph("• " + s, text))

elements.append(Spacer(1,16))

elements.append(Paragraph("ניסיון מקצועי", heading))
elements.append(Paragraph("<b>AI Infrastructure / MLOps Engineer</b> – שם החברה", text))
elements.append(Paragraph(
"• תכנון והקמה של תשתיות GPU עבור עומסי עבודה של למידת מכונה ו-LLM.<br/>"
"• פריסת מודלי שפה גדולים בסביבת Kubernetes / OpenShift.<br/>"
"• הקמת סביבת JupyterHub המאפשרת למדעני נתונים להריץ ניסויים על משאבי GPU משותפים.<br/>"
"• פיתוח כלי SDK ו-CLI לשימוש בפלטפורמת ה-ML של הארגון.<br/>"
"• בניית תהליכי CI/CD לפריסה אוטומטית של מודלים לסביבת ייצור.<br/>"
"• ניטור ושיפור ביצועים של שירותי inference.", text))

elements.append(Spacer(1,16))

elements.append(Paragraph("השכלה", heading))
elements.append(Paragraph("תואר ראשון בתחום רלוונטי – שם האוניברסיטה", text))

elements.append(Spacer(1,16))

elements.append(Paragraph("שפות", heading))
elements.append(Paragraph("עברית – שפת אם<br/>אנגלית – רמה מקצועית", text))

doc = SimpleDocTemplate(file_path, pagesize=A4)
doc.build(elements)

file_path