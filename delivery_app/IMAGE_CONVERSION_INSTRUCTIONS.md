# Image Conversion Instructions

The Rider Login screen is now styled to match the customer_app sign-in page. However, Flutter requires PNG/JPG image files, not PDF files.

## Current Status
- ✅ PDF file copied to: `delivery_app/assets/images/pic-rider.pdf`
- ⏳ Needs conversion to PNG: `delivery_app/assets/images/pic-rider.png`

## How to Convert PDF to PNG

### Option 1: Using Online Tools (Easiest)
1. Open `pic-rider.pdf` in a PDF viewer
2. Export/Save as PNG from the viewer, OR
3. Use an online converter like:
   - https://www.ilovepdf.com/pdf_to_jpg
   - https://cloudconvert.com/pdf-to-png
   - https://convertio.co/pdf-png/

### Option 2: Using ImageMagick (Command Line)
If you have ImageMagick installed:
```powershell
magick "delivery_app\assets\images\pic-rider.pdf[0]" "delivery_app\assets\images\pic-rider.png"
```

### Option 3: Using Adobe Acrobat
1. Open `pic-rider.pdf` in Adobe Acrobat
2. File > Export To > Image > PNG
3. Save as `pic-rider.png` in `delivery_app/assets/images/`

### Option 4: Using Windows Snipping Tool
1. Open the PDF in a PDF viewer
2. Take a screenshot using Snipping Tool
3. Save as PNG in `delivery_app/assets/images/pic-rider.png`

## After Conversion
Once you have `pic-rider.png` in `delivery_app/assets/images/`, the login screen will automatically display it.

The code is already set up to:
- Display the PNG image in the gradient header
- Fall back gracefully to a delivery icon if the image is not found
- Match the exact styling of the customer_app sign-in page

