#!/usr/bin/env python3
"""
Convert markdown to HTML with Confluence-compatible restrictions.

Allowed tags:
- h1, h2, h3, h4
- p
- ul, ol, li
- pre, code
- table, thead, tbody, tr, th, td
- a, img
- strong, em
- blockquote
- hr, br

Allowed attributes:
- a: href, title
- img: src, alt, title
- Everything else: no attributes
"""

import sys
import re
from html.parser import HTMLParser
from html import escape, unescape
import markdown


class ConfluenceHTMLSanitizer(HTMLParser):
    """Sanitize HTML to only allow Confluence-compatible tags and attributes."""
    
    ALLOWED_TAGS = {
        'h1', 'h2', 'h3', 'h4',
        'p',
        'ul', 'ol', 'li',
        'pre', 'code',
        'table', 'thead', 'tbody', 'tr', 'th', 'td',
        'a', 'img',
        'strong', 'em',
        'blockquote',
        'hr', 'br'
    }
    
    ALLOWED_ATTRS = {
        'a': {'href', 'title'},
        'img': {'src', 'alt', 'title'}
    }
    
    def __init__(self):
        super().__init__()
        self.output = []
        self.in_code_block = False
        
    def handle_starttag(self, tag, attrs):
        tag_lower = tag.lower()
        
        # Track code blocks to preserve content
        if tag_lower == 'pre' or tag_lower == 'code':
            self.in_code_block = True
        
        # Only process allowed tags
        if tag_lower not in self.ALLOWED_TAGS:
            return
        
        # Build attribute string
        attr_dict = dict(attrs)
        allowed_attrs = self.ALLOWED_ATTRS.get(tag_lower, set())
        
        # Filter attributes
        filtered_attrs = []
        for attr_name, attr_value in attrs:
            attr_name_lower = attr_name.lower()
            if attr_name_lower in allowed_attrs:
                # Escape attribute values
                escaped_value = escape(attr_value, quote=True)
                filtered_attrs.append(f'{attr_name_lower}="{escaped_value}"')
        
        # Build tag
        if filtered_attrs:
            self.output.append(f'<{tag_lower} {" ".join(filtered_attrs)}>')
        else:
            self.output.append(f'<{tag_lower}>')
    
    def handle_endtag(self, tag):
        tag_lower = tag.lower()
        
        # Track code blocks
        if tag_lower == 'pre' or tag_lower == 'code':
            self.in_code_block = False
        
        # Only output closing tags for allowed tags
        if tag_lower in self.ALLOWED_TAGS:
            self.output.append(f'</{tag_lower}>')
    
    def handle_data(self, data):
        # Preserve data as-is (will be escaped if needed)
        self.output.append(data)
    
    def handle_entityref(self, name):
        # Preserve HTML entities
        self.output.append(f'&{name};')
    
    def handle_charref(self, name):
        # Preserve numeric character references
        self.output.append(f'&#{name};')
    
    def get_output(self):
        return ''.join(self.output)


def sanitize_html(html_content):
    """Sanitize HTML content to only allow Confluence-compatible tags and attributes."""
    # First, handle code blocks specially - we need to preserve their content
    # Split by code blocks, process separately
    
    # Replace code blocks temporarily
    code_blocks = []
    code_block_pattern = r'<pre><code>(.*?)</code></pre>'
    
    def replace_code_block(match):
        code_content = match.group(1)
        placeholder = f'__CODE_BLOCK_{len(code_blocks)}__'
        code_blocks.append(code_content)
        return placeholder
    
    # Replace code blocks with placeholders
    html_with_placeholders = re.sub(
        code_block_pattern,
        replace_code_block,
        html_content,
        flags=re.DOTALL
    )
    
    # Also handle inline code
    inline_code_pattern = r'<code>(.*?)</code>'
    inline_codes = []
    
    def replace_inline_code(match):
        code_content = match.group(1)
        placeholder = f'__INLINE_CODE_{len(inline_codes)}__'
        inline_codes.append(code_content)
        return placeholder
    
    html_with_placeholders = re.sub(
        inline_code_pattern,
        replace_inline_code,
        html_with_placeholders,
        flags=re.DOTALL
    )
    
    # Sanitize the HTML
    sanitizer = ConfluenceHTMLSanitizer()
    sanitizer.feed(html_with_placeholders)
    sanitized = sanitizer.get_output()
    
    # Restore code blocks
    for i, code_content in enumerate(code_blocks):
        # Escape HTML in code blocks but preserve structure
        escaped_code = escape(code_content)
        sanitized = sanitized.replace(
            f'__CODE_BLOCK_{i}__',
            f'<pre><code>{escaped_code}</code></pre>'
        )
    
    for i, code_content in enumerate(inline_codes):
        escaped_code = escape(code_content)
        sanitized = sanitized.replace(
            f'__INLINE_CODE_{i}__',
            f'<code>{escaped_code}</code>'
        )
    
    return sanitized


def markdown_to_confluence_html(markdown_content):
    """Convert markdown to Confluence-compatible HTML."""
    # Convert markdown to HTML
    html = markdown.markdown(
        markdown_content,
        extensions=['tables', 'fenced_code', 'codehilite']
    )
    
    # Sanitize HTML
    sanitized = sanitize_html(html)
    
    return sanitized


def main():
    if len(sys.argv) != 3:
        print("Usage: python markdown_to_confluence.py <input.md> <output.html>", file=sys.stderr)
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            markdown_content = f.read()
        
        html_content = markdown_to_confluence_html(markdown_content)
        
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(html_content)
        
        print(f"Successfully converted {input_file} to {output_file}")
    
    except FileNotFoundError:
        print(f"Error: File not found: {input_file}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
