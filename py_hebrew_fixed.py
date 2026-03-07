# Generate a Hebrew CV PDF using reportlab with proper RTL support
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.units import cm
from reportlab.lib import colors
from bidi.algorithm import get_display
import os

# Find a Hebrew-supporting font
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
    try:
        pdfmetrics.registerFont(TTFont("HebrewFont", font_path))
        font_name = "HebrewFont"
    except:
        pass

styles = getSampleStyleSheet()

title = ParagraphStyle(
    "Title",
    parent=styles["Heading1"],
    fontName=font_name,
    fontSize=22,
    leading=26,
    alignment=2  # Right alignment for RTL
)

heading = ParagraphStyle(
    "Heading",
    parent=styles["Heading2"],
    fontName=font_name,
    fontSize=16,
    leading=20,
    alignment=2  # Right alignment for RTL
)

text = ParagraphStyle(
    "Text",
    parent=styles["BodyText"],
    fontName=font_name,
    fontSize=11,
    leading=16,
    alignment=2  # Right alignment for RTL
)

file_path = "./lscv_ai_infrastructure_hebrew.pdf"

# Ensure directory exists
os.makedirs(os.path.dirname(file_path) if os.path.dirname(file_path) else ".", exist_ok=True)

elements = []

# Hebrew text helper - converts to proper RTL format
def hebrew_text(text_str):
    return get_display(text_str)

elements.append(Paragraph(hebrew_text("קורות חיים – מהנדס תשתיות AI / MLOps"), title))
elements.append(Spacer(1, 20))

contact_data = [
    [hebrew_text("שם:"), hebrew_text("השם שלך")],
    [hebrew_text("טלפון:"), "050-0000000"],
    [hebrew_text("אימייל:"), "email@example.com"],
    [hebrew_text("LinkedIn:"), "linkedin.com/in/yourname"],
    [hebrew_text("GitHub:"), "github.com/yourname"],
    [hebrew_text("מיקום:"), hebrew_text("ישראל")]
]

table = Table(contact_data, colWidths=[4*cm, 12*cm])
table.setStyle(TableStyle([
    ('ALIGN', (0, 0), (-1, -1), 'RIGHT'),
    ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
    ('FONTNAME', (0, 0), (-1, -1), font_name),
    ('FONTSIZE', (0, 0), (-1, -1), 10),
]))
elements.append(table)
elements.append(Spacer(1, 20))

elements.append(Paragraph(hebrew_text("תקציר מקצועי"), heading))
elements.append(Paragraph(
    hebrew_text(
        "מהנדס תשתיות AI ו-MLOps עם ניסיון בבנייה והפעלה של פלטפורמות למידת מכונה ו-LLM בקנה מידה גדול. "
        "ניסיון בפריסת מודלים על Kubernetes ו-OpenShift עם תשתיות GPU, בניית סביבת עבודה למדעני נתונים "
        "באמצעות JupyterHub, ופיתוח כלי SDK ו-CLI המייעלים תהליכי עבודה של צוותי ML."
    ), text))
elements.append(Spacer(1, 16))

elements.append(Paragraph(hebrew_text("מיומנויות טכנולוגיות"), heading))
skills = [
    "LLM Deployment ו-Model Serving",
    "Kubernetes ו-OpenShift",
    hebrew_text("תשתיות GPU ועומסי עבודה של AI"),
    hebrew_text("JupyterHub וסביבות עבודה למדעני נתונים"),
    "Python ו-Bash",
    hebrew_text("פיתוח SDK ו-CLI לפלטפורמות ML"),
    hebrew_text("CI/CD למודלים של Machine Learning"),
    "Docker, Helm ו-Git",
    hebrew_text("Monitoring ו-Logging למערכות AI")
]

for s in skills:
    elements.append(Paragraph("• " + s, text))

elements.append(Spacer(1, 16))

elements.append(Paragraph(hebrew_text("ניסיון מקצועי"), heading))
elements.append(Paragraph("<b>AI Infrastructure / MLOps Engineer</b> – " + hebrew_text("שם החברה"), text))

# Experience details broken into separate paragraphs to avoid HTML parsing issues with RTL
experience_items = [
    "תכנון והקמה של תשתיות GPU עבור עומסי עבודה של למידת מכונה ו-LLM.",
    "פריסת מודלי שפה גדולים בסביבת Kubernetes / OpenShift.",
    "הקמת סביבת JupyterHub המאפשרת למדעני נתונים להריץ ניסויים על משאבי GPU משותפים.",
    "פיתוח כלי SDK ו-CLI לשימוש בפלטפורמת ה-ML של הארגון.",
    "בניית תהליכי CI/CD לפריסה אוטומטית של מודלים לסביבת ייצור.",
    "ניטור ושיפור ביצועים של שירותי inference."
]

for item in experience_items:
    elements.append(Paragraph("• " + hebrew_text(item), text))

elements.append(Spacer(1, 16))

elements.append(Paragraph(hebrew_text("השכלה"), heading))
elements.append(Paragraph(hebrew_text("תואר ראשון בתחום רלוונטי – שם האוניברסיטה"), text))

elements.append(Spacer(1, 16))

elements.append(Paragraph(hebrew_text("שפות"), heading))
elements.append(Paragraph(hebrew_text("עברית – שפת אם") + "<br/>" + hebrew_text("אנגלית – רמה מקצועית"), text))

doc = SimpleDocTemplate(file_path, pagesize=A4)
doc.build(elements)

print(f"PDF created successfully: {file_path}")
