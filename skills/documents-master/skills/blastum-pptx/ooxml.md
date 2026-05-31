# Office Open XML Technical Reference for PowerPoint

**Important: Read this entire document before starting.** Critical XML schema rules and formatting requirements are covered throughout. Incorrect implementation can create invalid PPTX files that PowerPoint cannot open.

## Technical Guidelines

### Schema Compliance
- **Element ordering in ` `**: ` `, ` `, ` `
- **Whitespace**: Add `xml:space='preserve'` to ` ` elements with leading/trailing spaces
- **Unicode**: Escape characters in ASCII content: `"` becomes `&#8220;`
- **Images**: Add to `ppt/media/`, reference in slide XML, set dimensions to fit slide bounds
- **Relationships**: Update `ppt/slides/_rels/slideN.xml.rels` for each slide's resources
- **Dirty attribute**: Add `dirty="0"` to ` ` and ` ` elements to indicate clean state

## Presentation Structure

### Basic Slide Structure
```xml
 
 
 
 
... 
... 
 
 
 
 
```

### Text Box / Shape with Text
```xml
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 Slide Title 
 
 
 
 
```

### Text Formatting
```xml
 
 
 
 Bold Text 
 

 
 
 
 Italic Text 
 

 
 
 
 Underlined 
 

 
 
 
 
 
 
 
 Highlighted Text 
 

 
 
 
 
 
 
 
 Colored Arial 24pt 
 

 
 
 
 
 
 
 
 Formatted text 
 
```

### Lists
```xml
 
 
 
 
 
 
 First bullet point 
 
 

 
 
 
 
 
 
 First numbered item 
 
 

 
 
 
 
 
 
 Indented bullet 
 
 
```

### Shapes
```xml
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 

 
 
 
 
 
 
 
 

 
 
 
 
 
 
 
 
```

### Images
```xml
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
```

### Tables
```xml
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 Cell 1 
 
 
 
 
 
 
 
 
 
 
 Cell 2 
 
 
 
 
 
 
 
 
 
```

### Slide Layouts

```xml
 
 
 
 
 
 
 
 
 

 
 
 
 
 
 
 
 

 
 
 
 
 
 
 
 
 

 
 
 
 
 
 
 
 
```

## File Updates

When adding content, update these files:

**`ppt/_rels/presentation.xml.rels`:**
```xml
 
 
```

**`ppt/slides/_rels/slide1.xml.rels`:**
```xml
 
 
```

**`[Content_Types].xml`:**
```xml
 
 
 
```

**`ppt/presentation.xml`:**
```xml
 
 
 
 
```

**`docProps/app.xml`:** Update slide count and statistics
```xml
 2 
 10 
 50 
```

## Slide Operations

### Adding a New Slide
When adding a slide to the end of the presentation:

1. **Create the slide file** (`ppt/slides/slideN.xml`)
2. **Update `[Content_Types].xml`**: Add Override for the new slide
3. **Update `ppt/_rels/presentation.xml.rels`**: Add relationship for the new slide
4. **Update `ppt/presentation.xml`**: Add slide ID to ` `
5. **Create slide relationships** (`ppt/slides/_rels/slideN.xml.rels`) if needed
6. **Update `docProps/app.xml`**: Increment slide count and update statistics (if present)

### Duplicating a Slide
1. Copy the source slide XML file with a new name
2. Update all IDs in the new slide to be unique
3. Follow the "Adding a New Slide" steps above
4. **CRITICAL**: Remove or update any notes slide references in `_rels` files
5. Remove references to unused media files

### Reordering Slides
1. **Update `ppt/presentation.xml`**: Reorder ` ` elements in ` `
2. The order of ` ` elements determines slide order
3. Keep slide IDs and relationship IDs unchanged

Example:
```xml
 
 
 
 
 
 

 
 
 
 
 
 
```

### Deleting a Slide
1. **Remove from `ppt/presentation.xml`**: Delete the ` ` entry
2. **Remove from `ppt/_rels/presentation.xml.rels`**: Delete the relationship
3. **Remove from `[Content_Types].xml`**: Delete the Override entry
4. **Delete files**: Remove `ppt/slides/slideN.xml` and `ppt/slides/_rels/slideN.xml.rels`
5. **Update `docProps/app.xml`**: Decrement slide count and update statistics
6. **Clean up unused media**: Remove orphaned images from `ppt/media/`

Note: Don't renumber remaining slides - keep their original IDs and filenames.


## Common Errors to Avoid

- **Encodings**: Escape unicode characters in ASCII content: `"` becomes `&#8220;`
- **Images**: Add to `ppt/media/` and update relationship files
- **Lists**: Omit bullets from list headers
- **IDs**: Use valid hexadecimal values for UUIDs
- **Themes**: Check all themes in `theme` directory for colors

## Validation Checklist for Template-Based Presentations

### Before Packing, Always:
- **Clean unused resources**: Remove unreferenced media, fonts, and notes directories
- **Fix Content_Types.xml**: Declare ALL slides, layouts, and themes present in the package
- **Fix relationship IDs**:
 - Remove font embed references if not using embedded fonts
- **Remove broken references**: Check all `_rels` files for references to deleted resources

### Common Template Duplication Pitfalls:
- Multiple slides referencing the same notes slide after duplication
- Image/media references from template slides that no longer exist
- Font embedding references when fonts aren't included
- Missing slideLayout declarations for layouts 12-25
- docProps directory may not unpack - this is optional