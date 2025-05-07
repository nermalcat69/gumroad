import DOMPurify from "dompurify";

/**
 * Sanitizes an HTML string using DOMPurify
 * Allows 'iframe' tags and 'src' attributes in addition to other default safe elements
 *
 * @param dirtyHtml The HTML string to sanitize.
 * @returns The sanitized HTML string.
 * @throws Error if called in a server-side environment
 */
export const sanitizeHtml = (dirtyHtml: string): string => {
  if (typeof window === "undefined") {
    throw new Error("sanitizeHtml can only be used in client-side environments");
  }

  // gumroad needs iframe tags to embed media
  return DOMPurify.sanitize(dirtyHtml, { ADD_TAGS: ["iframe"], ADD_ATTR: ["src"] });
};
