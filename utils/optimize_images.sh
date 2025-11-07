#!/bin/bash

# --- Configuration ---
# Set the JPEG quality and the PNG lossy compression quality range
JPEG_QUALITY=80
PNG_QUALITY="65-80"
# Use -q (quality for color) with a range of 0 (worst) to 100 (lossless)
AVIF_Q_LEVEL=75

# --- Tool Checks (AVIF may require installing 'libavif' or a utility like ImageMagick/sharp) ---
command -v pngquant >/dev/null 2>&1 || { echo >&2 "Error: pngquant is required but not installed. Aborting."; exit 1; }
command -v cwebp >/dev/null 2>&1 || { echo >&2 "Error: cwebp is required but not installed. Aborting."; exit 1; }
# Note: For AVIF, we will try to use 'avifenc' or fall back to 'convert' (ImageMagick)
if ! command -v avifenc >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
    echo >&2 "Warning: Neither 'avifenc' nor 'convert' (ImageMagick) found. AVIF file generation will be skipped."
    SKIP_AVIF=true
else
    SKIP_AVIF=false
fi

# Function to get file size in bytes (Cross-platform compatibility)
get_file_size() {
    # Try GNU stat first (Linux)
    if command -v stat >/dev/null 2>&1 && stat -c %s "$1" 2>/dev/null; then
        stat -c %s "$1"
    # Fallback to BSD/macOS stat
    elif command -v stat >/dev/null 2>&1; then
        stat -f %z "$1"
    else
        # If stat isn't available, use du, which is less precise but works
        du -b "$1" | awk '{print $1}'
    fi
}

# --- Input Validation ---
if [ -z "$1" ]; then
    echo "Usage: $0 <input_file.png>"
    exit 1
fi

INPUT_FILE="$1"
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found."
    exit 1
fi

if [[ "$INPUT_FILE" != *.png ]]; then
    echo "Error: Input file must be a PNG file."
    exit 1
fi

# --- File Naming ---
FILENAME_BASE=$(basename "$INPUT_FILE" .png)
DIRNAME=$(dirname "$INPUT_FILE")
OUTPUT_BASE="$DIRNAME/$FILENAME_BASE"

# --- 1. Create Optimized PNG (Lossy Quantization) ---
echo "Optimizing PNG to 8-bit paletted..."
OPTIMIZED_PNG_FILE="${OUTPUT_BASE}-fs8.png"
pngquant --quality="$PNG_QUALITY" --force --skip-if-larger --output "$OPTIMIZED_PNG_FILE" "$INPUT_FILE"

# Get file sizes for comparison
ORIGINAL_SIZE=$(get_file_size "$INPUT_FILE")

# Check if pngquant created a file
if [ -f "$OPTIMIZED_PNG_FILE" ]; then
    OPTIMIZED_SIZE=$(get_file_size "$OPTIMIZED_PNG_FILE")
    
    # Compare sizes
    if [ "$OPTIMIZED_SIZE" -ge "$ORIGINAL_SIZE" ]; then
        echo "  Optimized PNG was not smaller. Using original PNG as final PNG fallback."
        FINAL_PNG_FILE="$INPUT_FILE"
        # Clean up the unnecessary -fs8 file if it exists and is larger/not used
        rm -f "$OPTIMIZED_PNG_FILE"
    else
        echo "  Optimized PNG created: ${OPTIMIZED_PNG_FILE} (Size reduced from ${ORIGINAL_SIZE} to ${OPTIMIZED_SIZE} bytes)"
        FINAL_PNG_FILE="$OPTIMIZED_PNG_FILE"
    fi
else
    # If pngquant didn't create the file (likely due to --skip-if-larger)
    echo "  pngquant skipped creation or failed. Using original PNG as final PNG fallback."
    FINAL_PNG_FILE="$INPUT_FILE"
fi

# --- 2. Create JPEG (for photographic content fallback) ---
JPEG_FILE="${OUTPUT_BASE}.jpg"
echo ""
echo "Creating JPEG (Q=$JPEG_QUALITY)..."
# Use 'convert' (ImageMagick) for JPEG creation
convert "$INPUT_FILE" -quality "$JPEG_QUALITY" "$JPEG_FILE"
echo "  JPEG created: ${JPEG_FILE}"

# --- 3. Create WEBP ---
WEBP_FILE="${OUTPUT_BASE}.webp"
echo ""
echo "Creating WEBP..."
cwebp -q 75 "$INPUT_FILE" -o "$WEBP_FILE"
echo "  WEBP created: ${WEBP_FILE}"

# --- 4. Create AVIF ---
AVIF_FILE="${OUTPUT_BASE}.avif"
if [ "$SKIP_AVIF" = false ]; then
    echo ""
    echo "Creating AVIF (CQ=$AVIF_CQ_LEVEL)..."
    if command -v avifenc >/dev/null 2>&1; then
        avifenc "$INPUT_FILE" -o "$AVIF_FILE" -q "$AVIF_Q_LEVEL" -s 0
    else # Fallback to ImageMagick 'convert' for AVIF
        convert "$INPUT_FILE" -quality 70 "$AVIF_FILE" # ImageMagick uses a quality scale
    fi
    echo "  AVIF created: ${AVIF_FILE}"
else
    echo "AVIF generation skipped (tool not found)."
fi

# --- Final Output Paths (relative to script run location) ---
# Use the relative path for console output
REL_PNG=$(basename "$FINAL_PNG_FILE")
REL_JPEG=$(basename "$JPEG_FILE")
REL_WEBP=$(basename "$WEBP_FILE")
REL_AVIF=$(basename "$AVIF_FILE")

# --- 5. Print <picture> Element Snippet ---
echo ""
echo "========================================================================="
echo "🖼️ <picture> HTML SNIPPET"
echo "========================================================================="
echo "<picture>"
if [ "$SKIP_AVIF" = false ]; then
    echo "  <source srcset=\"$REL_AVIF\" type=\"image/avif\">"
fi
echo "  <source srcset=\"$REL_WEBP\" type=\"image/webp\">"
echo "  <img src=\"$REL_JPEG\" alt=\"Descriptive alt text\" loading=\"lazy\">"
echo "  <!-- img src=\"$REL_PNG\" alt=\"Descriptive alt text\" loading=\"lazy\" -->"
echo "</picture>"
echo ""

# --- 6. Print background-image: image-set() Snippet ---
echo ""
echo "========================================================================="
echo "✨ background-image: image-set() CSS SNIPPET (Modern Browsers)"
echo "========================================================================="
echo ".my-element {"
echo "  background-image: url(\"$REL_JPEG\"); /* Base Fallback for all browsers */"
echo "  /* background-image: url(\"$REL_PNG\"); /* Base Fallback for all browsers */"
echo "  background-image: image-set("
if [ "$SKIP_AVIF" = false ]; then
    echo "    \"$REL_AVIF\" type(\"image/avif\"),"
fi
echo "    \"$REL_WEBP\" type(\"image/webp\"),"
echo "    \"$REL_JPEG\" type(\"image/jpeg\")"
echo "    /* \"$REL_PNG\" type(\"image/png\") */"
echo "  );"
echo "}"
echo "========================================================================="