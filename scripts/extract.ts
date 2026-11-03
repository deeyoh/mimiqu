type ExtractionField = {
  name: string;
  selector: string;
  kind: "text" | "html" | "attribute";
  attribute: string | null;
  required: boolean;
};

/**
 * Runs in the browser through CDP Runtime.evaluate.
 * Returns a JSON string for ScrapeResponse.data_json.
 * Keep this as a plain script: the Zig wrapper calls extract(fields).
 */
const extract = (fields: readonly ExtractionField[]): string => {
  if (fields.length === 0) {
    if (document.documentElement === null) {
      throw new Error("Document has no root element");
    }

    return JSON.stringify({
      html: document.documentElement.outerHTML,
    });
  }

  // A null prototype also makes names such as "__proto__" safe as keys.
  const output: Record<string, string | null> = Object.create(null);

  for (const field of fields) {
    // Invalid CSS selectors throw and become CDP exceptionDetails.
    const element = document.querySelector(field.selector);
    let value: string | null = null;

    if (element !== null) {
      switch (field.kind) {
        case "text":
          value = element.textContent;
          break;
        case "html":
          value = element.innerHTML;
          break;
        case "attribute":
          if (field.attribute === null || field.attribute.length === 0) {
            throw new Error(`Missing attribute name for field: ${field.name}`);
          }
          value = element.getAttribute(field.attribute);
          break;
        default:
          throw new Error(`Unsupported extraction kind for field: ${field.name}`);
      }
    }

    // Empty strings are valid values. Only absent values fail required fields.
    if (field.required && value === null) {
      throw new Error(`Missing required field: ${field.name}`);
    }

    output[field.name] = value;
  }

  return JSON.stringify(output);
};
