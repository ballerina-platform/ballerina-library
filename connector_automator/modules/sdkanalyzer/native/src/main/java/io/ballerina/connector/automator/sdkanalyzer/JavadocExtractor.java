package io.ballerina.connector.automator.sdkanalyzer;

import java.io.File;
import java.io.InputStream;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.Map;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;

import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;
import org.jsoup.select.Elements;

/**
 * Simple Javadoc HTML extractor that builds a map of
 * fully-qualified-class-name -> (memberName -> shortDescription)
 *
 * The extractor scans HTML files inside a javadoc.jar and reads
 * the summary tables (Method Summary, Field Summary, Enum Constant Summary)
 * and extracts short descriptions for members.
 */
public class JavadocExtractor {

    /**
     * Load javadoc from a javadoc JAR file.
     * Returns an index mapping class FQNs (dot form) to a map of member->description.
     */
    public static Map<String, Map<String, String>> loadFromJar(File javadocJar) {
        Map<String, Map<String, String>> index = new HashMap<>();
        if (javadocJar == null || !javadocJar.exists()) {
            return index;
        }

        try (JarFile jar = new JarFile(javadocJar)) {
            Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                String name = entry.getName();
                if (!name.endsWith(".html")) continue;
                // skip package-summary and index pages
                if (name.endsWith("package-summary.html") || name.endsWith("index.html")) continue;

                try (InputStream in = jar.getInputStream(entry)) {
                    Document doc = Jsoup.parse(in, "UTF-8", "");

                    String classFqnDot = name.replace('/', '.').replaceAll("\\.html$", "");
                    Map<String, String> members = index.getOrDefault(classFqnDot, new HashMap<>());

                    // Helper to record a member description
                    java.util.function.BiConsumer<String, String> record = (member, desc) -> {
                        if (member == null || member.isEmpty() || desc == null) return;
                        String trimmed = desc.trim();
                        if (trimmed.length() == 0) return;
                        int dot = trimmed.indexOf('.');
                        if (dot > 30) dot = -1;
                        String shortDesc = (dot > 0) ? trimmed.substring(0, dot + 1).trim() : trimmed.split("\\n")[0].trim();
                        members.put(member, shortDesc);
                    };

                    // Attempt to find summary tables
                    Elements tables = doc.select("table");
                    for (Element table : tables) {
                        String caption = "";
                        Element cap = table.selectFirst("caption");
                        if (cap != null) caption = cap.text().toLowerCase();

                        String prevText = "";
                        Element prev = table.previousElementSibling();
                        if (prev != null) prevText = prev.text().toLowerCase();

                        boolean isMethodSummary = caption.contains("method summary") || caption.contains("all methods") || prevText.contains("method summary") || prevText.contains("methods");
                        boolean isFieldSummary = caption.contains("field summary") || prevText.contains("field summary") || prevText.contains("fields") || caption.contains("enum constant summary") || prevText.contains("enum constant summary");

                        if (!isMethodSummary && !isFieldSummary) continue;

                        Elements rows = table.select("tr");
                        for (Element row : rows) {
                            String memberName = null;
                            String desc = null;

                            Element colSecond = row.selectFirst("th.colSecond");
                            Element colLast = row.selectFirst("td.colLast");

                            if (colSecond != null && colLast != null) {
                                // Extract method name from colSecond
                                Element memberLink = colSecond.selectFirst(".memberNameLink a");
                                if (memberLink != null) {
                                    String linkText = memberLink.text();
                                    int p = linkText.indexOf('(');
                                    memberName = (p > 0) ? linkText.substring(0, p).trim() : linkText.trim();
                                } else {
                                    Element code = colSecond.selectFirst("code");
                                    if (code != null) {
                                        String codeText = code.text();
                                        int p = codeText.indexOf('(');
                                        memberName = (p > 0) ? codeText.substring(0, p).trim() : codeText.trim();
                                    }
                                }

                                // Extract description from colLast
                                Element block = colLast.selectFirst("div.block");
                                desc = (block != null) ? block.text() : colLast.text();
                            } else {
                                Elements cols = row.select("td");
                                if (cols.size() >= 2) {
                                    Element nameCol = cols.get(0);
                                    Element descCol = cols.get(1);

                                    Element codeEl = nameCol.selectFirst("code");
                                    if (codeEl != null) {
                                        String codeText = codeEl.text();
                                        int p = codeText.indexOf('(');
                                        memberName = (p > 0) ? codeText.substring(0, p).trim() : codeText.trim();
                                    } else {
                                        Element a = nameCol.selectFirst("a");
                                        if (a != null) {
                                            memberName = a.text().trim();
                                        } else {
                                            String t = nameCol.text();
                                            int p = t.indexOf('(');
                                            memberName = (p > 0) ? t.substring(0, p).trim() : t.trim();
                                        }
                                    }

                                    desc = descCol.text();
                                }
                            }

                            if (memberName != null && !memberName.isEmpty()) {
                                record.accept(memberName, desc);
                            }
                        }
                    }

                    if (!members.isEmpty()) {
                        index.put(classFqnDot, members);
                        int lastDot = classFqnDot.lastIndexOf('.');
                        if (lastDot > 0) {
                            String alt = classFqnDot.substring(0, lastDot) + "$" + classFqnDot.substring(lastDot + 1);
                            if (!index.containsKey(alt)) {
                                index.put(alt, members);
                            }
                        }

                    }

                } catch (Exception e) {
                    System.err.println("Failed to parse Javadoc entry: " + name + " - " + e.getMessage());
                }
            }
        } catch (Exception e) {
            return index;
        }

        return index;
    }

    /**
     * Load javadoc from a javadoc JAR file, but only for specified classes and members.
     * This is more efficient when you only need javadoc for a subset of classes.
     * 
     * @param javadocJar The javadoc JAR file
     * @param classNames Set of fully-qualified class names to extract (e.g., "com.example.MyClass")
     * @param memberNames Optional set of member names to extract (if null/empty, extract all members for matched classes)
     * @return Map of class FQNs to member descriptions
     */
    public static Map<String, Map<String, String>> loadFilteredFromJar(File javadocJar, java.util.Set<String> classNames, java.util.Set<String> memberNames) {
        Map<String, Map<String, String>> index = new HashMap<>();
        if (javadocJar == null || !javadocJar.exists() || classNames == null || classNames.isEmpty()) {
            return index;
        }

        java.util.Set<String> normalizedNames = new java.util.HashSet<>();
        for (String cn : classNames) {
            normalizedNames.add(cn);
            // Add variants
            normalizedNames.add(cn.replace('$', '.'));
            normalizedNames.add(cn.replace('.', '$'));
        }

        try (JarFile jar = new JarFile(javadocJar)) {
            Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                String name = entry.getName();
                if (!name.endsWith(".html")) continue;
                if (name.endsWith("package-summary.html") || name.endsWith("index.html")) continue;

                String classFqnDot = name.replace('/', '.').replaceAll("\\.html$", "");
                
                boolean isTarget = false;
                for (String target : normalizedNames) {
                    if (classFqnDot.equals(target) || classFqnDot.equals(target.replace('$', '.')) || classFqnDot.equals(target.replace('.', '$'))) {
                        isTarget = true;
                        break;
                    }
                }
                
                if (!isTarget) continue;

                try (InputStream in = jar.getInputStream(entry)) {
                    Document doc = Jsoup.parse(in, "UTF-8", "");

                    Map<String, String> members = index.getOrDefault(classFqnDot, new HashMap<>());

                    // Helper to record a member description
                    java.util.function.BiConsumer<String, String> record = (member, desc) -> {
                        if (member == null || member.isEmpty() || desc == null) return;
                        if (memberNames != null && !memberNames.isEmpty() && !memberNames.contains(member)) {
                            return;
                        }
                        String trimmed = desc.trim();
                        if (trimmed.length() == 0) return;
                        int dot = trimmed.indexOf('.');
                        if (dot > 30) dot = -1;
                        String shortDesc = (dot > 0) ? trimmed.substring(0, dot + 1).trim() : trimmed.split("\\n")[0].trim();
                        members.put(member, shortDesc);
                    };

                    // Attempt to find summary tables
                    Elements tables = doc.select("table");
                    for (Element table : tables) {
                        String caption = "";
                        Element cap = table.selectFirst("caption");
                        if (cap != null) caption = cap.text().toLowerCase();

                        String prevText = "";
                        Element prev = table.previousElementSibling();
                        if (prev != null) prevText = prev.text().toLowerCase();

                        boolean isMethodSummary = caption.contains("method summary") || caption.contains("all methods") || prevText.contains("method summary") || prevText.contains("methods");
                        boolean isFieldSummary = caption.contains("field summary") || prevText.contains("field summary") || prevText.contains("fields") || caption.contains("enum constant summary") || prevText.contains("enum constant summary");

                        if (!isMethodSummary && !isFieldSummary) continue;

                        Elements rows = table.select("tr");
                        for (Element row : rows) {
                            String memberName = null;
                            String desc = null;

                            Element colSecond = row.selectFirst("th.colSecond");
                            Element colLast = row.selectFirst("td.colLast");

                            if (colSecond != null && colLast != null) {
                                Element memberLink = colSecond.selectFirst(".memberNameLink a");
                                if (memberLink != null) {
                                    String linkText = memberLink.text();
                                    int p = linkText.indexOf('(');
                                    memberName = (p > 0) ? linkText.substring(0, p).trim() : linkText.trim();
                                } else {
                                    Element code = colSecond.selectFirst("code");
                                    if (code != null) {
                                        String codeText = code.text();
                                        int p = codeText.indexOf('(');
                                        memberName = (p > 0) ? codeText.substring(0, p).trim() : codeText.trim();
                                    }
                                }

                                // Extract description from colLast
                                Element block = colLast.selectFirst("div.block");
                                desc = (block != null) ? block.text() : colLast.text();
                            } else {
                                Elements cols = row.select("td");
                                if (cols.size() >= 2) {
                                    Element nameCol = cols.get(0);
                                    Element descCol = cols.get(1);

                                    Element codeEl = nameCol.selectFirst("code");
                                    if (codeEl != null) {
                                        String codeText = codeEl.text();
                                        int p = codeText.indexOf('(');
                                        memberName = (p > 0) ? codeText.substring(0, p).trim() : codeText.trim();
                                    } else {
                                        Element a = nameCol.selectFirst("a");
                                        if (a != null) {
                                            memberName = a.text().trim();
                                        } else {
                                            String t = nameCol.text();
                                            int p = t.indexOf('(');
                                            memberName = (p > 0) ? t.substring(0, p).trim() : t.trim();
                                        }
                                    }

                                    desc = descCol.text();
                                }
                            }

                            if (memberName != null && !memberName.isEmpty()) {
                                record.accept(memberName, desc);
                            }
                        }
                    }

                    if (!members.isEmpty()) {
                        index.put(classFqnDot, members);
                        int lastDot = classFqnDot.lastIndexOf('.');
                        if (lastDot > 0) {
                            String alt = classFqnDot.substring(0, lastDot) + "$" + classFqnDot.substring(lastDot + 1);
                            if (!index.containsKey(alt)) {
                                index.put(alt, members);
                            }
                        }

                    }

                } catch (Exception e) {
                    System.err.println("Failed to parse Javadoc entry: " + name + " - " + e.getMessage());
                }
            }
        } catch (Exception e) {
            return index;
        }

        return index;
    }
}
