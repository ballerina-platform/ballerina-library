// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
package io.ballerina.connector.automator.sdkanalyzer;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;

import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassVisitor;
import org.objectweb.asm.MethodVisitor;
import org.objectweb.asm.Opcodes;

import com.github.javaparser.JavaParser;
import com.github.javaparser.ParserConfiguration;
import com.github.javaparser.ast.CompilationUnit;
import com.github.javaparser.ast.Modifier;
import com.github.javaparser.ast.NodeList;
import com.github.javaparser.ast.body.ClassOrInterfaceDeclaration;
import com.github.javaparser.ast.body.ConstructorDeclaration;
import com.github.javaparser.ast.body.EnumConstantDeclaration;
import com.github.javaparser.ast.body.EnumDeclaration;
import com.github.javaparser.ast.body.FieldDeclaration;
import com.github.javaparser.ast.body.MethodDeclaration;
import com.github.javaparser.ast.body.Parameter;
import com.github.javaparser.ast.body.TypeDeclaration;
import com.github.javaparser.ast.body.VariableDeclarator;
import com.github.javaparser.ast.comments.JavadocComment;
import com.github.javaparser.ast.type.ClassOrInterfaceType;
import com.github.javaparser.ast.type.Type;

import io.ballerina.runtime.api.creators.ErrorCreator;
import io.ballerina.runtime.api.creators.TypeCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.MapType;
import io.ballerina.runtime.api.types.PredefinedTypes;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BString;

/**
 * JavaParser-based analyzer for Java SDK JARs.
 * This replaces the reflection-based approach with static source analysis
 * using JavaParser and ASM for bytecode analysis when sources are not available.
 */
public class JavaParserAnalyzer {

    private static final Set<String> EXCLUDED_PACKAGES = Set.of(
            "sun", "com.sun", "jdk", "java.lang", "java.util", "java.io", 
            "java.net", "java.time", "java.concurrent", "javax"
    );
    // Optional javadoc index: classFQN -> (memberName -> description)
    private static Map<String, Map<String, String>> javadocIndex = null;
    private static final Set<String> LOGGED_RESOLVED_CLASSES = new HashSet<>();

    private static boolean isVerboseEnabled() {
        String env = System.getenv("SDK_VERBOSE");
        if (env == null) {
            return false;
        }
        String lower = env.toLowerCase();
        return "1".equals(lower) || "true".equals(lower) || "yes".equals(lower);
    }

    private static void logInfo(String message) {
        if (isVerboseEnabled()) {
            System.err.println("INFO: " + message);
        }
    }

    private static Map<String, String> findJavadocMapForClass(String className) {
        if (javadocIndex == null || className == null) return null;
        // Exact match
        Map<String, String> map = javadocIndex.get(className);
        if (map != null) return map;

        map = javadocIndex.get(className.replace('$', '.'));
        if (map != null) return map;

        int lastDot = className.lastIndexOf('.');
        String simple = (lastDot >= 0) ? className.substring(lastDot + 1) : className;

        for (String key : javadocIndex.keySet()) {
            if (key.endsWith("." + simple) || key.endsWith(".class-use." + simple) || key.endsWith("$" + simple) || key.equals(simple)) {
                return javadocIndex.get(key);
            }
            if (key.contains("." + simple + "")) {
                return javadocIndex.get(key);
            }
        }
        return null;
    }

    /**
     * Analyze JAR using JavaParser approach.
     * This is the main entry point that replaces the reflection-based parsing.
     *
     * @param jarPathOrResult JAR path or Maven resolution result
     * @return Parsed class information
     */
    @SuppressWarnings("unchecked")
    public static Object analyzeJarWithJavaParser(Object jarPathOrResult) {
        try {
            List<File> jarFiles = new ArrayList<>();
            String mainJarPath;
            
            if (jarPathOrResult instanceof BMap) {
                BMap<BString, Object> mavenResult = (BMap<BString, Object>) jarPathOrResult;
                
                Object allJarsObj = mavenResult.get(StringUtils.fromString("allJars"));
                if (allJarsObj instanceof BArray allJars) {
                    for (int i = 0; i < allJars.getLength(); i++) {
                        String jarPath = allJars.getBString(i).getValue();
                        File jarFile = new File(jarPath);
                        if (jarFile.exists()) {
                            jarFiles.add(jarFile);
                        }
                    }
                }
                
                mainJarPath = mavenResult.get(StringUtils.fromString("mainJar")).toString();
            } else {
                String jarPath = jarPathOrResult.toString();
                File jarFile = new File(jarPath);
                
                if (!jarFile.exists()) {
                    return ErrorCreator.createError(
                            StringUtils.fromString("JAR file not found: " + jarPath));
                }
                
                mainJarPath = jarPath;
                jarFiles.add(jarFile);
            }
            
            if (jarFiles.isEmpty()) {
                return ErrorCreator.createError(
                        StringUtils.fromString("No JARs to analyze"));
            }
            
            logInfo("Analyzing " + jarFiles.size() + " JAR file(s) with JavaParser");
            
            // 1. List all classes in the main JAR
            List<String> classNames = listAllClasses(new File(mainJarPath));
            logInfo("Found " + classNames.size() + " classes");
            
            // 2. Extract source files and analyze with JavaParser
            List<BMap<BString, Object>> classes = new ArrayList<>();

            String explicitSourcesPath = null;
            String explicitJavadocPath = null;
            if (jarPathOrResult instanceof BMap) {
                BMap<BString, Object> mavenResult = (BMap<BString, Object>) jarPathOrResult;
                Object sourcesObj = mavenResult.get(StringUtils.fromString("sourcesPath"));
                if (sourcesObj != null) {
                    explicitSourcesPath = sourcesObj.toString();
                }
                Object javadocObj = mavenResult.get(StringUtils.fromString("javadocPath"));
                if (javadocObj != null) {
                    explicitJavadocPath = javadocObj.toString();
                }
            }

            Map<String, CompilationUnit> parsedSources = extractAndParseSourceFiles(jarFiles, explicitSourcesPath);

            logInfo("Parsed " + parsedSources.size() + " source files");

            try {
                if (explicitJavadocPath != null && !explicitJavadocPath.isEmpty()) {
                    File javadocJar = new File(explicitJavadocPath);
                    if (javadocJar.exists()) {
                        logInfo("Loading javadoc from explicit path: " + javadocJar.getAbsolutePath());
                        javadocIndex = JavadocExtractor.loadFromJar(javadocJar);
                        int size = javadocIndex == null ? 0 : javadocIndex.size();
                        logInfo("Loaded javadoc entries for " + size + " classes");
                    } else {
                        System.err.println("WARNING: Explicit javadoc JAR not found: " + explicitJavadocPath);
                    }
                } else {
                    File mainJarFile = new File(mainJarPath);
                    File parent = mainJarFile.getParentFile();
                    if (parent != null && parent.exists()) {
                        File[] candidates = parent.listFiles((dir, name) -> name.toLowerCase().contains("javadoc") && name.endsWith(".jar"));
                        if (candidates == null || candidates.length == 0) {
                        } else {
                            File javadocJar = candidates[0];
                            logInfo("Found javadoc jar: " + javadocJar.getAbsolutePath());
                            javadocIndex = JavadocExtractor.loadFromJar(javadocJar);
                            int size = javadocIndex == null ? 0 : javadocIndex.size();
                            logInfo("Loaded javadoc entries for " + size + " classes");
                        }
                    }
                }

            } catch (Exception e) {
                System.err.println("WARNING: JavaParserAnalyzer javadoc loading failed: " + e.getMessage());
            }
            
            // 3. For each class, create metadata using JavaParser + ASM fallback
            for (String className : classNames) {
                if (shouldIncludeClass(className)) {
                    try {
                        BMap<BString, Object> classInfo = analyzeClassWithJavaParser(
                                className, parsedSources, jarFiles);
                        if (classInfo != null) {
                            classes.add(classInfo);
                        }
                    } catch (Exception e) {
                        System.err.println("WARNING: Failed to analyze class " + className + ": " + e.getMessage());
                    }
                }
            }
            
            logInfo("Successfully analyzed " + classes.size() + " classes");
            
            // Convert to BArray
            MapType mapType = TypeCreator.createMapType(PredefinedTypes.TYPE_JSON);
            return ValueCreator.createArrayValue(classes.toArray(BMap[]::new),
                    TypeCreator.createArrayType(mapType));
            
        } catch (IOException e) {
            return ErrorCreator.createError(
                    StringUtils.fromString("JavaParser analysis failed: " + e.getMessage()));
        }
    }
    
    /**
     * Find all concrete classes in a set of JAR files that directly implement or extend the
     * given interface or abstract class.  Uses ASM in metadata-only mode (SKIP_CODE) for speed.
     *
     * @param interfaceFqn Fully qualified interface/abstract class name (dot-separated)
     * @param jarPaths     Array of JAR file paths to search
     * @return BArray of fully qualified concrete implementing class names (may be empty)
     */
    public static Object findImplementorsInJars(BString interfaceFqn, BArray jarPaths) {
        try {
            String targetInterface = interfaceFqn.getValue().replace('.', '/');
            String topPackage = "";
            int dotIdx = targetInterface.indexOf('/');
            if (dotIdx > 0) {
                int secondDot = targetInterface.indexOf('/', dotIdx + 1);
                if (secondDot > 0) {
                    topPackage = targetInterface.substring(0, secondDot);
                } else {
                    topPackage = targetInterface.substring(0, dotIdx);
                }
            }

            List<String> implementors = new ArrayList<>();

            for (int i = 0; i < jarPaths.getLength(); i++) {
                String jarPath = jarPaths.getBString(i).getValue();
                File jarFile = new File(jarPath);
                if (!jarFile.exists()) continue;

                try (JarFile jar = new JarFile(jarFile)) {
                    Enumeration<JarEntry> entries = jar.entries();
                    while (entries.hasMoreElements()) {
                        JarEntry entry = entries.nextElement();
                        String entryName = entry.getName();
                        if (!entryName.endsWith(".class")) continue;
                        if (entryName.contains("$")) continue;
                        if (!topPackage.isEmpty() && !entryName.startsWith(topPackage)) continue;
                        String lowerEntry = entryName.toLowerCase(java.util.Locale.ROOT);
                        if (lowerEntry.contains("/internal/") || lowerEntry.contains("/impl/")) continue;

                        try (InputStream is = jar.getInputStream(entry)) {
                            ClassReader cr = new ClassReader(is);
                            final boolean[] matched = {false};
                            cr.accept(new ClassVisitor(Opcodes.ASM9) {
                                @Override
                                public void visit(int version, int access, String name,
                                        String signature, String superName, String[] interfaces) {
                                    boolean isAbstract  = (access & Opcodes.ACC_ABSTRACT)  != 0;
                                    boolean isInterface = (access & Opcodes.ACC_INTERFACE) != 0;
                                    boolean isEnum      = (access & Opcodes.ACC_ENUM)      != 0;
                                    boolean isPublic    = (access & Opcodes.ACC_PUBLIC)    != 0;
                                    if (!isPublic || isAbstract || isInterface || isEnum) return;
                                    if (interfaces != null) {
                                        for (String iface : interfaces) {
                                            if (targetInterface.equals(iface)) {
                                                matched[0] = true;
                                                break;
                                            }
                                        }
                                    }
                                    if (!matched[0] && targetInterface.equals(superName)) {
                                        matched[0] = true;
                                    }
                                    if (matched[0]) {
                                        String className = name.replace('/', '.');
                                        implementors.add(className);
                                    }
                                }
                            }, ClassReader.SKIP_CODE | ClassReader.SKIP_DEBUG | ClassReader.SKIP_FRAMES);
                        } catch (Exception ignored) {}
                    }
                } catch (Exception ignored) {}
            }

            BString[] result = implementors.stream()
                    .map(StringUtils::fromString)
                    .toArray(BString[]::new);
            return ValueCreator.createArrayValue(result);

        } catch (Exception e) {
            System.err.println("WARNING: findImplementorsInJars failed: " + e.getMessage());
            return ValueCreator.createArrayValue(new BString[0]);
        }
    }

    /**
     * Resolve a single class from a list of JAR files.
     * This is used for lazy resolution of external dependency classes (e.g., parent builder classes).
     *
     * @param className Fully qualified class name to resolve
     * @param jarPaths Array of JAR file paths to search
     * @return Class info BMap or null if not found
     */
    public static Object resolveClassFromJars(BString className, BArray jarPaths) {
        try {
            String classNameStr = className.getValue();
            List<File> jarFiles = new ArrayList<>();
            
            for (int i = 0; i < jarPaths.getLength(); i++) {
                String jarPath = jarPaths.getBString(i).getValue();
                File jarFile = new File(jarPath);
                if (jarFile.exists()) {
                    jarFiles.add(jarFile);
                }
            }
            
            if (jarFiles.isEmpty()) {
                return null;
            }
            
            // Try to analyze the class with ASM from the JAR files
            MapType mapType = TypeCreator.createMapType(PredefinedTypes.TYPE_JSON);
            BMap<BString, Object> classInfo = ValueCreator.createMapValue(mapType);
            
            // Basic class information
            classInfo.put(StringUtils.fromString("className"), StringUtils.fromString(classNameStr));
            
            String packageName = "";
            String simpleName = classNameStr;
            if (classNameStr.contains(".")) {
                int lastDot = classNameStr.lastIndexOf(".");
                packageName = classNameStr.substring(0, lastDot);
                simpleName = classNameStr.substring(lastDot + 1);
            }
            
            classInfo.put(StringUtils.fromString("packageName"), StringUtils.fromString(packageName));
            classInfo.put(StringUtils.fromString("simpleName"), StringUtils.fromString(simpleName));
            
            // Try to find and analyze with ASM
            BMap<BString, Object> result = analyzeWithASM(classNameStr, jarFiles, classInfo);
            
            Object methods = result.get(StringUtils.fromString("methods"));
            if (methods instanceof BArray methodsArray) {
                Object superClass = result.get(StringUtils.fromString("superClass"));
                Object interfaces = result.get(StringUtils.fromString("interfaces"));
                if (methodsArray.getLength() > 0 || superClass != null || 
                    (interfaces instanceof BArray && ((BArray) interfaces).getLength() > 0)) {
                    if (LOGGED_RESOLVED_CLASSES.add(classNameStr)) {
                        logInfo("Resolved external class: " + classNameStr);
                    }
                    return result;
                }
            }
            
            return null;
            
        } catch (Exception e) {
            System.err.println("WARNING: Failed to resolve class " + className.getValue() + ": " + e.getMessage());
            return null;
        }
    }
    
    /**
     * List all classes in a JAR file.
     *
     * @param jarFile JAR file to scan
     * @return List of class names
     */
    private static List<String> listAllClasses(File jarFile) throws IOException {
        List<String> classNames = new ArrayList<>();
        
        try (JarFile jar = new JarFile(jarFile)) {
            Enumeration<JarEntry> entries = jar.entries();
            
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                String entryName = entry.getName();
                
                if (entryName.endsWith(".class")) {
                    String baseName = entryName.substring(0, entryName.length() - 6); 
                    boolean isAnonymous = false;
                    if (baseName.contains("$")) {
                        String[] segments = baseName.split("\\$");
                        for (int si = 1; si < segments.length; si++) {
                            if (!segments[si].isEmpty() && segments[si].chars().allMatch(Character::isDigit)) {
                                isAnonymous = true;
                                break;
                            }
                        }
                    }
                    if (isAnonymous) {
                        continue;
                    }
                    String className = baseName.replace('/', '.');
                    classNames.add(className);
                }
            }
        }
        
        return classNames;
    }
    
    /**
     * Extract and parse source files from JARs.
     *
     * @param jarFiles List of JAR files
     * @return Map of class name to CompilationUnit
     */
    private static Map<String, CompilationUnit> extractAndParseSourceFiles(List<File> jarFiles, String sourcesPath) {
        Map<String, CompilationUnit> parsedSources = new HashMap<>();

        // Configure JavaParser with basic settings
        ParserConfiguration config = new ParserConfiguration();
        config.setLanguageLevel(ParserConfiguration.LanguageLevel.JAVA_17);

        JavaParser javaParser = new JavaParser(config);

        // 1) Extract .java from provided sourcesPath (if any)
        if (sourcesPath != null && !sourcesPath.isBlank()) {
            File sp = new File(sourcesPath);
            if (sp.exists()) {
                if (sp.isDirectory()) {
                    // Walk directory for .java files
                    try {
                        java.nio.file.Files.walk(sp.toPath())
                                .filter(p -> p.toString().endsWith(".java"))
                                .forEach(p -> {
                                    try {
                                            String content = java.nio.file.Files.readString(p);
                                            CompilationUnit cu = javaParser.parse(content).getResult().orElse(null);
                                            if (cu != null) {
                                                // Derive a fallback path from the file path relative to the sources root
                                                String fallbackPath = sp.toPath().relativize(p).toString().replace(java.io.File.separatorChar, '/');
                                                String className = extractClassNameFromCU(cu, fallbackPath);
                                                if (className != null) {
                                                    parsedSources.put(className, cu);
                                                }
                                            }
                                    } catch (IOException e) {
                                        System.err.println("WARNING: Failed to parse source file " + p + ": " + e.getMessage());
                                    }
                                });
                    } catch (IOException e) {
                        System.err.println("WARNING: Failed to read sources directory: " + sp.getAbsolutePath());
                    }
                } else if (sp.isFile() && sp.getName().endsWith(".jar")) {
                    // Read .java entries from the provided sources JAR
                    try (JarFile srcJar = new JarFile(sp)) {
                        Enumeration<JarEntry> entries = srcJar.entries();
                        while (entries.hasMoreElements()) {
                            JarEntry entry = entries.nextElement();
                            String entryName = entry.getName();
                                if (entryName.endsWith(".java")) {
                                try (InputStream inputStream = srcJar.getInputStream(entry)) {
                                    String content = new String(inputStream.readAllBytes());
                                    try {
                                        var parseResult = javaParser.parse(content);
                                        Optional<CompilationUnit> opt = parseResult.getResult();
                                        if (opt.isPresent()) {
                                            CompilationUnit cu = opt.get();
                                            // Use the jar entry path as a fallback if JavaParser doesn't provide a primary type
                                            String className = extractClassNameFromCU(cu, entryName);
                                            if (className != null) {
                                                parsedSources.put(className, cu);
                                            }
                                        } else {
                                            System.err.println("WARNING: parse returned empty for " + entryName + ", problems=" + parseResult.getProblems());
                                        }
                                    } catch (Exception e) {
                                        System.err.println("WARNING: Failed to parse " + entryName + ": " + e.getMessage());
                                    }
                                }
                            }
                        }
                    } catch (IOException e) {
                        System.err.println("WARNING: Failed to read sources JAR: " + sp.getName());
                    }
                }
            } else {
                logInfo("sourcesPath provided but not found: " + sourcesPath);
            }
        }

        // 2) Fallback: Extract .java files that may be present inside the main JARs
        for (File jarFile : jarFiles) {
            try (JarFile jar = new JarFile(jarFile)) {
                Enumeration<JarEntry> entries = jar.entries();

                while (entries.hasMoreElements()) {
                    JarEntry entry = entries.nextElement();
                    String entryName = entry.getName();

                    // Look for .java files
                    if (entryName.endsWith(".java")) {
                        try (InputStream inputStream = jar.getInputStream(entry)) {
                            String content = new String(inputStream.readAllBytes());

                            try {
                                CompilationUnit cu = javaParser.parse(content).getResult().orElse(null);
                                if (cu != null) {
                                    // Extract class name from compilation unit; use jar entry as fallback
                                    String className = extractClassNameFromCU(cu, entryName);
                                    if (className != null) {
                                        parsedSources.put(className, cu);
                                    }
                                }
                            } catch (Exception e) {
                                System.err.println("WARNING: Failed to parse " + entryName + ": " + e.getMessage());
                            }
                        }
                    }
                }
            } catch (IOException e) {
                System.err.println("WARNING: Failed to read JAR: " + jarFile.getName());
            }
        }

        return parsedSources;
    }
    
    /**
     * Extract class name from CompilationUnit.
     *
     * @param cu CompilationUnit
     * @return Fully qualified class name
     */
    private static String extractClassNameFromCU(CompilationUnit cu, String fallbackPath) {
        Optional<String> packageName = cu.getPackageDeclaration()
                .map(pd -> pd.getNameAsString());

        Optional<TypeDeclaration<?>> primaryType = cu.getPrimaryType();
        if (primaryType.isPresent()) {
            String className = primaryType.get().getNameAsString();
            return packageName.map(pkg -> pkg + "." + className).orElse(className);
        }

        // If no primary type, try to derive from the fallbackPath (jar entry or relative path)
        if (fallbackPath != null && !fallbackPath.isBlank()) {
            String candidate = fallbackPath.replace('/', '.');
            if (candidate.endsWith(".java")) {
                candidate = candidate.substring(0, candidate.length() - 5);
            }
            // If package declaration exists, prefer it
            if (packageName.isPresent()) {
                // If candidate already contains package, return it; otherwise combine
                if (candidate.startsWith(packageName.get())) {
                    return candidate;
                } else {
                    // Use simple name from candidate if present
                    int lastDot = candidate.lastIndexOf('.');
                    String simple = lastDot >= 0 ? candidate.substring(lastDot + 1) : candidate;
                    return packageName.get() + "." + simple;
                }
            }

            return candidate;
        }

        return null;
    }
    
    /**
     * Analyze a single class using JavaParser + ASM fallback.
     *
     * @param className Class name to analyze
     * @param parsedSources Parsed source files
     * @param jarFiles JAR files for ASM analysis
     * @return Class information map
     */
    private static BMap<BString, Object> analyzeClassWithJavaParser(
            String className, 
            Map<String, CompilationUnit> parsedSources, 
            List<File> jarFiles) throws Exception {
        
        MapType mapType = TypeCreator.createMapType(PredefinedTypes.TYPE_JSON);
        BMap<BString, Object> classInfo = ValueCreator.createMapValue(mapType);
        
        // Basic class information
        classInfo.put(StringUtils.fromString("className"), StringUtils.fromString(className));
        
        String packageName = "";
        String simpleName = className;
        if (className.contains(".")) {
            int lastDot = className.lastIndexOf(".");
            packageName = className.substring(0, lastDot);
            simpleName = className.substring(lastDot + 1);
        }
        
        classInfo.put(StringUtils.fromString("packageName"), StringUtils.fromString(packageName));
        classInfo.put(StringUtils.fromString("simpleName"), StringUtils.fromString(simpleName));
        
        // Try JavaParser first (if source available)
        CompilationUnit cu = parsedSources.get(className);
        if (cu != null) {
            return analyzeWithJavaParserSource(className, cu, classInfo);
        }
        
        // Fallback to ASM for bytecode analysis
        return analyzeWithASM(className, jarFiles, classInfo);
    }
    
    /**
     * Analyze class using JavaParser with source code.
     *
     * @param className Class name
     * @param cu CompilationUnit
     * @param classInfo Base class info map
     * @return Complete class information
     */
    private static BMap<BString, Object> analyzeWithJavaParserSource(
            String className, 
            CompilationUnit cu, 
            BMap<BString, Object> classInfo) {
        
        MapType mapType = TypeCreator.createMapType(PredefinedTypes.TYPE_JSON);
        
        String simpleName = className.contains(".") ? className.substring(className.lastIndexOf('.') + 1) : className;
        TypeDeclaration<?> typeDecl = null;

        for (TypeDeclaration<?> td : cu.getTypes()) {
            if (td.getNameAsString().equals(simpleName)) {
                typeDecl = td;
                break;
            }
        }

        if (typeDecl == null) {
            Optional<TypeDeclaration<?>> primaryType = cu.getPrimaryType();
            if (primaryType.isPresent()) {
                typeDecl = primaryType.get();
            } else if (!cu.getTypes().isEmpty()) {
                typeDecl = cu.getTypes().get(0);
            } else {
                return null;
            }
        }
        
        // Basic type information
        classInfo.put(StringUtils.fromString("isInterface"), typeDecl.isClassOrInterfaceDeclaration() && 
                typeDecl.asClassOrInterfaceDeclaration().isInterface());
        classInfo.put(StringUtils.fromString("isAbstract"), typeDecl.hasModifier(Modifier.Keyword.ABSTRACT));
        classInfo.put(StringUtils.fromString("isEnum"), typeDecl.isEnumDeclaration());
        classInfo.put(StringUtils.fromString("isDeprecated"), typeDecl.isAnnotationPresent("Deprecated"));
        
        // Handle enum types
        if (typeDecl.isEnumDeclaration()) {
            EnumDeclaration enumDecl = typeDecl.asEnumDeclaration();
            
            // Extract enum constants
            List<BMap<BString, Object>> fields = new ArrayList<>();
            for (EnumConstantDeclaration enumConst : enumDecl.getEntries()) {
                BMap<BString, Object> fieldInfo = ValueCreator.createMapValue(mapType);
                fieldInfo.put(StringUtils.fromString("name"), StringUtils.fromString(enumConst.getNameAsString()));
                fieldInfo.put(StringUtils.fromString("type"), StringUtils.fromString(className));
                fieldInfo.put(StringUtils.fromString("isStatic"), true);
                fieldInfo.put(StringUtils.fromString("isFinal"), true);
                fieldInfo.put(StringUtils.fromString("isDeprecated"), enumConst.isAnnotationPresent("Deprecated"));
                
                // Javadoc for enum constant
                Optional<JavadocComment> javadoc = enumConst.getJavadocComment();
                if (javadoc.isPresent()) {
                    fieldInfo.put(StringUtils.fromString("javadoc"), 
                            StringUtils.fromString(javadoc.get().getContent()));
                } else {
                    fieldInfo.put(StringUtils.fromString("javadoc"), null);
                }
                
                fields.add(fieldInfo);
            }
            
            classInfo.put(StringUtils.fromString("fields"),
                    ValueCreator.createArrayValue(fields.toArray(BMap[]::new), 
                    TypeCreator.createArrayType(mapType)));
            
            // Enums don't have constructors or methods we care about for this use case
            classInfo.put(StringUtils.fromString("methods"),
                    ValueCreator.createArrayValue(new BMap[0], 
                    TypeCreator.createArrayType(mapType)));
            classInfo.put(StringUtils.fromString("constructors"),
                    ValueCreator.createArrayValue(new BMap[0], 
                    TypeCreator.createArrayType(mapType)));
            
            classInfo.put(StringUtils.fromString("superClass"), null);
            classInfo.put(StringUtils.fromString("genericSuperClass"), StringUtils.fromString(""));
            classInfo.put(StringUtils.fromString("interfaces"), ValueCreator.createArrayValue(new BString[0]));
            
            // Annotations
            String[] annotations = enumDecl.getAnnotations().stream()
                    .map(ann -> ann.getNameAsString())
                    .toArray(String[]::new);
            BString[] annotationsB = new BString[annotations.length];
            for (int i = 0; i < annotations.length; i++) {
                annotationsB[i] = StringUtils.fromString(annotations[i]);
            }
            classInfo.put(StringUtils.fromString("annotations"), ValueCreator.createArrayValue(annotationsB));
            
            return classInfo;
        }
        
        if (typeDecl.isClassOrInterfaceDeclaration()) {
            ClassOrInterfaceDeclaration classDecl = typeDecl.asClassOrInterfaceDeclaration();
            
            // Superclass
            Optional<Type> superclass = classDecl.getExtendedTypes().isEmpty() ? 
                    Optional.empty() : 
                    Optional.of(classDecl.getExtendedTypes().get(0));
            
            if (superclass.isPresent()) {
                String superClassName = superclass.get().asString();
                if (!superClassName.equals("Object")) {
                    classInfo.put(StringUtils.fromString("superClass"), StringUtils.fromString(superClassName));
                    Type superType = superclass.get();
                    if (superType.isClassOrInterfaceType() && 
                        superType.asClassOrInterfaceType().getTypeArguments().isPresent()) {
                        classInfo.put(StringUtils.fromString("genericSuperClass"),
                                StringUtils.fromString(superType.asString()));
                    } else {
                        classInfo.put(StringUtils.fromString("genericSuperClass"), StringUtils.fromString(""));
                    }
                } else {
                    classInfo.put(StringUtils.fromString("superClass"), null);
                    classInfo.put(StringUtils.fromString("genericSuperClass"), StringUtils.fromString(""));
                }
            } else {
                classInfo.put(StringUtils.fromString("superClass"), null);
                classInfo.put(StringUtils.fromString("genericSuperClass"), StringUtils.fromString(""));
            }
            
            // Interfaces
            NodeList<ClassOrInterfaceType> implementedTypes = classDecl.getImplementedTypes();
            BString[] interfaceNames = implementedTypes.stream()
                    .map(type -> StringUtils.fromString(type.asString()))
                    .toArray(BString[]::new);
            classInfo.put(StringUtils.fromString("interfaces"), ValueCreator.createArrayValue(interfaceNames));
            
            // Extract methods
            List<BMap<BString, Object>> methods = new ArrayList<>();
            for (MethodDeclaration method : classDecl.getMethods()) {
                if (method.isPublic()) {
                    methods.add(analyzeMethodWithJavaParser(className, method, mapType));
                }
            }
            classInfo.put(StringUtils.fromString("methods"),
                    ValueCreator.createArrayValue(methods.toArray(BMap[]::new), 
                    TypeCreator.createArrayType(mapType)));
            
            // Extract fields
            List<BMap<BString, Object>> fields = new ArrayList<>();
            for (FieldDeclaration field : classDecl.getFields()) {
                if (field.isPublic()) {
                    fields.addAll(analyzeFieldWithJavaParser(className, field, mapType));
                }
            }
            classInfo.put(StringUtils.fromString("fields"),
                    ValueCreator.createArrayValue(fields.toArray(BMap[]::new), 
                    TypeCreator.createArrayType(mapType)));
            
            // Extract constructors
            List<BMap<BString, Object>> constructors = new ArrayList<>();
            for (ConstructorDeclaration constructor : classDecl.getConstructors()) {
                if (constructor.isPublic()) {
                    constructors.add(analyzeConstructorWithJavaParser(className, constructor, mapType));
                }
            }
            classInfo.put(StringUtils.fromString("constructors"),
                    ValueCreator.createArrayValue(constructors.toArray(BMap[]::new), 
                    TypeCreator.createArrayType(mapType)));
        }
        
        // Annotations
        String[] annotations = typeDecl.getAnnotations().stream()
                .map(ann -> ann.getNameAsString())
                .toArray(String[]::new);
        BString[] annotationsB = new BString[annotations.length];
        for (int i = 0; i < annotations.length; i++) {
            annotationsB[i] = StringUtils.fromString(annotations[i]);
        }
        classInfo.put(StringUtils.fromString("annotations"), ValueCreator.createArrayValue(annotationsB));
        
        return classInfo;
    }
    
    /**
     * Analyze method using JavaParser.
     *
     * @param method MethodDeclaration
     * @param mapType Map type for creating values
     * @return Method information map
     */
        private static BMap<BString, Object> analyzeMethodWithJavaParser(
            String className, MethodDeclaration method, MapType mapType) {
        
        BMap<BString, Object> methodInfo = ValueCreator.createMapValue(mapType);
        
        methodInfo.put(StringUtils.fromString("name"), StringUtils.fromString(method.getNameAsString()));
        methodInfo.put(StringUtils.fromString("returnType"), 
                StringUtils.fromString(method.getType().asString()));
        methodInfo.put(StringUtils.fromString("isStatic"), method.isStatic());
        methodInfo.put(StringUtils.fromString("isFinal"), method.isFinal());
        methodInfo.put(StringUtils.fromString("isAbstract"), method.isAbstract());
        methodInfo.put(StringUtils.fromString("isDeprecated"), method.isAnnotationPresent("Deprecated"));
        
        // Javadoc: prefer inline source javadoc, fallback to extracted javadoc index
        Optional<JavadocComment> javadoc = method.getJavadocComment();
        if (javadoc.isPresent()) {
            methodInfo.put(StringUtils.fromString("javadoc"),
                    StringUtils.fromString(javadoc.get().getContent()));
        } else {
            String fallback = null;
            try {
                Map<String, String> classMap = findJavadocMapForClass(className);
                if (classMap != null) {
                    // Try exact method name first; then try some normalized variants
                    String mname = method.getNameAsString();
                    String desc = classMap.get(mname);
                    if (desc == null) {
                        // some javadocs include suffixes or builder qualifiers; try last token
                        int dot = mname.lastIndexOf('.');
                        if (dot >= 0) desc = classMap.get(mname.substring(dot + 1));
                    }
                    if (desc == null) {
                        // try method + "()" form
                        desc = classMap.get(method.getNameAsString() + "()");
                    }
                    if (desc != null) fallback = desc;
                }
            } catch (Exception ignored) {}
            methodInfo.put(StringUtils.fromString("javadoc"), fallback == null ? null : StringUtils.fromString(fallback));
        }
        
            // Parameters
        List<BMap<BString, Object>> paramList = new ArrayList<>();
        for (Parameter param : method.getParameters()) {
            BMap<BString, Object> paramInfo = ValueCreator.createMapValue(mapType);
            paramInfo.put(StringUtils.fromString("name"), StringUtils.fromString(param.getNameAsString()));
            paramInfo.put(StringUtils.fromString("type"), StringUtils.fromString(param.getTypeAsString()));
            paramInfo.put(StringUtils.fromString("isVarArgs"), param.isVarArgs());
                if (param.getTypeAsString().endsWith("Request")) {
                    try {
                        Map<String, String> classMap = findJavadocMapForClass(param.getTypeAsString());
                        if (classMap == null) {
                            classMap = findJavadocMapForClass(param.getTypeAsString() + ".Builder");
                        }

                        if (classMap != null && !classMap.isEmpty()) {
                            List<BMap<BString, Object>> rflds = new ArrayList<>();
                            for (Map.Entry<String, String> e : classMap.entrySet()) {
                                String member = e.getKey();
                                String desc = e.getValue();
                                if (member == null || member.isBlank()) continue;
                                if (member.contains("<") || member.contains(" ")) continue;

                                BMap<BString, Object> f = ValueCreator.createMapValue(mapType);
                                f.put(StringUtils.fromString("name"), StringUtils.fromString(member));
                                f.put(StringUtils.fromString("type"), StringUtils.fromString(""));
                                f.put(StringUtils.fromString("isDeprecated"), false);
                                f.put(StringUtils.fromString("javadoc"), desc == null ? null : StringUtils.fromString(desc));
                                rflds.add(f);
                            }
                            paramInfo.put(StringUtils.fromString("requestFields"),
                                    ValueCreator.createArrayValue(rflds.toArray(BMap[]::new), TypeCreator.createArrayType(mapType)));
                        } else {
                            paramInfo.put(StringUtils.fromString("requestFields"),
                                    ValueCreator.createArrayValue(new BMap[0], TypeCreator.createArrayType(mapType)));
                        }
                    } catch (Exception ignored) {
                        paramInfo.put(StringUtils.fromString("requestFields"),
                                ValueCreator.createArrayValue(new BMap[0], TypeCreator.createArrayType(mapType)));
                    }
                }
            
            paramList.add(paramInfo);
        }
        methodInfo.put(StringUtils.fromString("parameters"),
                ValueCreator.createArrayValue(paramList.toArray(BMap[]::new), 
                TypeCreator.createArrayType(mapType)));
        
        // Exceptions
        String[] exceptionNames = method.getThrownExceptions().stream()
                .map(Type::asString)
                .toArray(String[]::new);
        BString[] exceptionNamesB = new BString[exceptionNames.length];
        for (int i = 0; i < exceptionNames.length; i++) {
            exceptionNamesB[i] = StringUtils.fromString(exceptionNames[i]);
        }
        methodInfo.put(StringUtils.fromString("exceptions"), ValueCreator.createArrayValue(exceptionNamesB));
        
        return methodInfo;
    }
    
    /**
     * Analyze field using JavaParser.
     *
     * @param field FieldDeclaration
     * @param mapType Map type for creating values
     * @return List of field information maps (one per variable)
     */
        private static List<BMap<BString, Object>> analyzeFieldWithJavaParser(
            String className, FieldDeclaration field, MapType mapType) {
        
        List<BMap<BString, Object>> fields = new ArrayList<>();
        
        for (VariableDeclarator variable : field.getVariables()) {
            BMap<BString, Object> fieldInfo = ValueCreator.createMapValue(mapType);
            
            fieldInfo.put(StringUtils.fromString("name"), StringUtils.fromString(variable.getNameAsString()));
            fieldInfo.put(StringUtils.fromString("type"), StringUtils.fromString(variable.getTypeAsString()));
            fieldInfo.put(StringUtils.fromString("isStatic"), field.isStatic());
            fieldInfo.put(StringUtils.fromString("isFinal"), field.isFinal());
            fieldInfo.put(StringUtils.fromString("isDeprecated"), field.isAnnotationPresent("Deprecated"));
            
            // Javadoc: prefer inline source javadoc, fallback to extracted javadoc index
            Optional<JavadocComment> javadoc = field.getJavadocComment();
            if (javadoc.isPresent()) {
                fieldInfo.put(StringUtils.fromString("javadoc"),
                        StringUtils.fromString(javadoc.get().getContent()));
            } else {
                String fallback = null;
                try {
                    Map<String, String> classMap = findJavadocMapForClass(className);
                    if (classMap != null) {
                        String fname = variable.getNameAsString();
                        String desc = classMap.get(fname);
                        if (desc == null) {
                            int dot = fname.lastIndexOf('.');
                            if (dot >= 0) desc = classMap.get(fname.substring(dot + 1));
                        }
                        if (desc != null) fallback = desc;
                    }
                } catch (Exception ignored) {}
                fieldInfo.put(StringUtils.fromString("javadoc"), fallback == null ? null : StringUtils.fromString(fallback));
            }
            
            fields.add(fieldInfo);
        }
        
        return fields;
    }
    
    /**
     * Analyze constructor using JavaParser.
     *
     * @param constructor ConstructorDeclaration  
     * @param mapType Map type for creating values
     * @return Constructor information map
     */
        private static BMap<BString, Object> analyzeConstructorWithJavaParser(
            String className, ConstructorDeclaration constructor, MapType mapType) {
        
        BMap<BString, Object> constructorInfo = ValueCreator.createMapValue(mapType);
        
        constructorInfo.put(StringUtils.fromString("isDeprecated"), constructor.isAnnotationPresent("Deprecated"));
        
        // Javadoc: prefer inline source javadoc, fallback to extracted javadoc index
        Optional<JavadocComment> javadoc = constructor.getJavadocComment();
        if (javadoc.isPresent()) {
            constructorInfo.put(StringUtils.fromString("javadoc"),
                    StringUtils.fromString(javadoc.get().getContent()));
        } else {
            String fallback = null;
            try {
                if (javadocIndex != null) {
                    Map<String, String> classMap = javadocIndex.get(className);
                    if (classMap == null) {
                        classMap = javadocIndex.get(className.replace('$', '.'));
                    }
                    if (classMap != null) {
                        String simple = constructor.getNameAsString();
                        String desc = classMap.get(simple);
                        if (desc == null) desc = classMap.get("<init>");
                        if (desc != null) fallback = desc;
                    }
                }
            } catch (Exception ignored) {}
            constructorInfo.put(StringUtils.fromString("javadoc"), fallback == null ? null : StringUtils.fromString(fallback));
        }
        
        // Parameters
        List<BMap<BString, Object>> paramList = new ArrayList<>();
        for (Parameter param : constructor.getParameters()) {
            BMap<BString, Object> paramInfo = ValueCreator.createMapValue(mapType);
            paramInfo.put(StringUtils.fromString("name"), StringUtils.fromString(param.getNameAsString()));
            paramInfo.put(StringUtils.fromString("type"), StringUtils.fromString(param.getTypeAsString()));
            paramInfo.put(StringUtils.fromString("isVarArgs"), param.isVarArgs());
            paramList.add(paramInfo);
        }
        constructorInfo.put(StringUtils.fromString("parameters"),
                ValueCreator.createArrayValue(paramList.toArray(BMap[]::new), 
                TypeCreator.createArrayType(mapType)));
        
        // Exceptions
        String[] exceptionNames = constructor.getThrownExceptions().stream()
                .map(Type::asString)
                .toArray(String[]::new);
        BString[] exceptionNamesB = new BString[exceptionNames.length];
        for (int i = 0; i < exceptionNames.length; i++) {
            exceptionNamesB[i] = StringUtils.fromString(exceptionNames[i]);
        }
        constructorInfo.put(StringUtils.fromString("exceptions"), ValueCreator.createArrayValue(exceptionNamesB));
        
        return constructorInfo;
    }
    
    /**
     * Analyze class using ASM bytecode analysis (fallback when source not available).
     *
     * @param className Class name
     * @param jarFiles JAR files to search
     * @param classInfo Base class info map
     * @return Complete class information
     */
    private static BMap<BString, Object> analyzeWithASM(
            String className, List<File> jarFiles, BMap<BString, Object> classInfo) throws Exception {
        
        MapType mapType = TypeCreator.createMapType(PredefinedTypes.TYPE_JSON);
        
        // Find and analyze class with ASM
        for (File jarFile : jarFiles) {
            try (JarFile jar = new JarFile(jarFile)) {
                String classPath = className.replace('.', '/') + ".class";
                JarEntry entry = jar.getJarEntry(classPath);
                
                if (entry != null) {
                    try (InputStream inputStream = jar.getInputStream(entry)) {
                        ClassReader classReader = new ClassReader(inputStream);
                        
                        ASMClassAnalyzer analyzer = new ASMClassAnalyzer(classInfo, mapType);
                        classReader.accept(analyzer, ClassReader.SKIP_DEBUG);
                        
                        return classInfo;
                    }
                }
            }
        }
        
        // If not found, return basic info
        classInfo.put(StringUtils.fromString("isInterface"), false);
        classInfo.put(StringUtils.fromString("isAbstract"), false);
        classInfo.put(StringUtils.fromString("isEnum"), false);
        classInfo.put(StringUtils.fromString("isDeprecated"), false);
        classInfo.put(StringUtils.fromString("superClass"), null);
        classInfo.put(StringUtils.fromString("genericSuperClass"), StringUtils.fromString(""));
        classInfo.put(StringUtils.fromString("interfaces"), ValueCreator.createArrayValue(new BString[0]));
        classInfo.put(StringUtils.fromString("annotations"), ValueCreator.createArrayValue(new BString[0]));
        classInfo.put(StringUtils.fromString("methods"), ValueCreator.createArrayValue(new BMap[0], 
                TypeCreator.createArrayType(mapType)));
        classInfo.put(StringUtils.fromString("fields"), ValueCreator.createArrayValue(new BMap[0], 
                TypeCreator.createArrayType(mapType)));
        classInfo.put(StringUtils.fromString("constructors"), ValueCreator.createArrayValue(new BMap[0], 
                TypeCreator.createArrayType(mapType)));
        
        return classInfo;
    }
    
    /**
     * Check if class should be included in analysis.
     *
     * @param className Class name
     * @return True if should be included
     */
    private static boolean shouldIncludeClass(String className) {
        if (className.contains("$")) {
            String[] segments = className.split("\\$");
            for (int si = 1; si < segments.length; si++) {
                if (!segments[si].isEmpty() && segments[si].chars().allMatch(Character::isDigit)) {
                    return false;
                }
            }
        }

        // Skip excluded packages
        for (String excludedPackage : EXCLUDED_PACKAGES) {
            if (className.startsWith(excludedPackage + ".")) {
                return false;
            }
        }

        return true;
    }
    
    /**
     * ASM ClassVisitor for analyzing bytecode.
     */
    private static class ASMClassAnalyzer extends ClassVisitor {
        
        private final BMap<BString, Object> classInfo;
        private final MapType mapType;
        private final List<BMap<BString, Object>> methods = new ArrayList<>();
        private final List<BMap<BString, Object>> fields = new ArrayList<>();
        private final List<BMap<BString, Object>> constructors = new ArrayList<>();
        private boolean isEnum = false;
        private String enumClassName = "";

        private final java.util.LinkedHashMap<String, BMap<BString, Object>> pendingConstantHolderFields
                = new java.util.LinkedHashMap<>();
        private final Map<String, String> constantHolderStringValues = new HashMap<>();
        
        public ASMClassAnalyzer(BMap<BString, Object> classInfo, MapType mapType) {
            super(Opcodes.ASM9);
            this.classInfo = classInfo;
            this.mapType = mapType;
        }
        
        @Override
        public void visit(int version, int access, String name, String signature, 
                String superName, String[] interfaces) {
            
            // Class type information
            boolean isInterface = (access & Opcodes.ACC_INTERFACE) != 0;
            boolean isAbstract = (access & Opcodes.ACC_ABSTRACT) != 0;
            this.isEnum = (access & Opcodes.ACC_ENUM) != 0;
            this.enumClassName = name.replace('/', '.');
            
            classInfo.put(StringUtils.fromString("isInterface"), isInterface);
            classInfo.put(StringUtils.fromString("isAbstract"), isAbstract);
            classInfo.put(StringUtils.fromString("isEnum"), this.isEnum);
            
            // Superclass
            if (superName != null && !superName.equals("java/lang/Object")) {
                classInfo.put(StringUtils.fromString("superClass"), 
                        StringUtils.fromString(superName.replace('/', '.')));
            } else {
                classInfo.put(StringUtils.fromString("superClass"), null);
            }
            
            String genericSuperStr = "";
            if (signature != null && superName != null && !superName.equals("java/lang/Object")) {
                String superDesc = "L" + superName + "<";
                int idx = signature.indexOf(superDesc);
                if (idx >= 0) {
                    int start = idx + superDesc.length();
                    int depth = 1;
                    int end = start;
                    while (end < signature.length() && depth > 0) {
                        char c = signature.charAt(end);
                        if (c == '<') depth++;
                        else if (c == '>') depth--;
                        end++;
                    }
                    if (depth == 0) {
                        String paramsPart = signature.substring(start, end - 1);
                        StringBuilder sb = new StringBuilder();
                        sb.append(superName.replace('/', '.'));
                        sb.append('<');
                        int pi = 0;
                        boolean first = true;
                        while (pi < paramsPart.length()) {
                            if (paramsPart.charAt(pi) == 'L') {
                                int semi = paramsPart.indexOf(';', pi);
                                if (semi > pi) {
                                    if (!first) sb.append(',');
                                    String raw = paramsPart.substring(pi + 1, semi);
                                    int genIdx = raw.indexOf('<');
                                    if (genIdx >= 0) {
                                        sb.append(raw.substring(0, genIdx).replace('/', '.'));
                                    } else {
                                        sb.append(raw.replace('/', '.'));
                                    }
                                    first = false;
                                    pi = semi + 1;
                                } else { pi++; }
                            } else { pi++; }
                        }
                        sb.append('>');
                        genericSuperStr = sb.toString();
                    }
                }
            }
            classInfo.put(StringUtils.fromString("genericSuperClass"),
                    StringUtils.fromString(genericSuperStr));

            // Interfaces
            BString[] interfaceNames = new BString[interfaces.length];
            for (int i = 0; i < interfaces.length; i++) {
                interfaceNames[i] = StringUtils.fromString(interfaces[i].replace('/', '.'));
            }
            classInfo.put(StringUtils.fromString("interfaces"), ValueCreator.createArrayValue(interfaceNames));
        }
        
        @Override
        public org.objectweb.asm.FieldVisitor visitField(int access, String name, String descriptor,
                String signature, Object value) {

            boolean isPublic  = (access & Opcodes.ACC_PUBLIC)  != 0;
            boolean isStatic  = (access & Opcodes.ACC_STATIC)  != 0;
            boolean isFinal   = (access & Opcodes.ACC_FINAL)   != 0;
            boolean isEnumCst = (access & Opcodes.ACC_ENUM)    != 0;

            // Skip synthetic/compiler-generated names
            if (name.startsWith("$") || name.startsWith("this$")) {
                return null;
            }

            // Pattern A: Java enum constants — always extracted
            boolean extractAsEnum = isEnum && isPublic && isStatic && isFinal && isEnumCst;

            boolean extractAsConstantHolder = false;
            if (!isEnum && isPublic && isStatic && isFinal && descriptor != null) {
                String selfDesc = "L" + enumClassName.replace('.', '/') + ";";
                extractAsConstantHolder = descriptor.equals(selfDesc);
            }

            boolean extractAsInstanceField = !isStatic && !isEnumCst && !extractAsEnum && !extractAsConstantHolder;
            if (extractAsInstanceField) {
                String fieldTypeName = descriptorToClassName(descriptor);
                BMap<BString, Object> fieldInfo = ValueCreator.createMapValue(mapType);
                fieldInfo.put(StringUtils.fromString("name"), StringUtils.fromString(name));
                fieldInfo.put(StringUtils.fromString("type"), StringUtils.fromString(fieldTypeName));
                fieldInfo.put(StringUtils.fromString("typeName"), StringUtils.fromString(fieldTypeName));
                fieldInfo.put(StringUtils.fromString("fullType"), StringUtils.fromString(fieldTypeName));
                fieldInfo.put(StringUtils.fromString("isStatic"), false);
                fieldInfo.put(StringUtils.fromString("isFinal"), isFinal);
                fieldInfo.put(StringUtils.fromString("isDeprecated"), false);
                fieldInfo.put(StringUtils.fromString("javadoc"), (Object) null);
                fields.add(fieldInfo);
            }

            if (extractAsEnum || extractAsConstantHolder) {
                BMap<BString, Object> fieldInfo = ValueCreator.createMapValue(mapType);
                fieldInfo.put(StringUtils.fromString("name"), StringUtils.fromString(name));
                fieldInfo.put(StringUtils.fromString("type"), StringUtils.fromString(enumClassName));
                fieldInfo.put(StringUtils.fromString("typeName"), StringUtils.fromString(enumClassName));
                fieldInfo.put(StringUtils.fromString("fullType"), StringUtils.fromString(enumClassName));
                fieldInfo.put(StringUtils.fromString("isStatic"), true);
                fieldInfo.put(StringUtils.fromString("isFinal"), true);
                fieldInfo.put(StringUtils.fromString("isDeprecated"), false);

                // Attach javadoc if available
                String fieldJavadoc = null;
                try {
                    if (javadocIndex != null) {
                        Map<String, String> classMap = javadocIndex.get(enumClassName);
                        if (classMap == null) {
                            classMap = javadocIndex.get(enumClassName.replace('$', '.'));
                        }
                        if (classMap != null) {
                            String desc = classMap.get(name);
                            if (desc != null) fieldJavadoc = desc;
                        }
                    }
                } catch (Exception ignored) {}
                fieldInfo.put(StringUtils.fromString("javadoc"),
                        fieldJavadoc == null ? null : StringUtils.fromString(fieldJavadoc));

                if (extractAsEnum) {
                    fields.add(fieldInfo);
                } else {
                    pendingConstantHolderFields.put(name, fieldInfo);
                }
            }

            return null;
        }
        
        @Override
        public MethodVisitor visitMethod(int access, String name, String descriptor,
                String signature, String[] exceptions) {

            if (name.equals("<clinit>") && !pendingConstantHolderFields.isEmpty()) {
                return new ConstantHolderInitVisitor(enumClassName, constantHolderStringValues);
            }

            // Only include public methods
            if ((access & Opcodes.ACC_PUBLIC) != 0) {
                BMap<BString, Object> methodInfo = ValueCreator.createMapValue(mapType);
                
                methodInfo.put(StringUtils.fromString("name"), StringUtils.fromString(name));
                
                // Use signature to extract generic return type if available, otherwise fallback to descriptor
                String returnType;
                if (signature != null && !signature.isEmpty()) {
                    returnType = extractReturnTypeFromSignature(signature);
                } else {
                    returnType = extractReturnTypeFromDescriptor(descriptor);
                }
                methodInfo.put(StringUtils.fromString("returnType"), StringUtils.fromString(returnType));
                
                methodInfo.put(StringUtils.fromString("isStatic"), (access & Opcodes.ACC_STATIC) != 0);
                methodInfo.put(StringUtils.fromString("isFinal"), (access & Opcodes.ACC_FINAL) != 0);
                methodInfo.put(StringUtils.fromString("isAbstract"), (access & Opcodes.ACC_ABSTRACT) != 0);
                methodInfo.put(StringUtils.fromString("isDeprecated"), false); 
                String methodJavadoc = null;
                try {
                    if (javadocIndex != null) {
                        Map<String, String> classMap = javadocIndex.get(enumClassName);
                        if (classMap == null) {
                            classMap = javadocIndex.get(enumClassName.replace('$', '.'));
                        }
                        if (classMap != null) {
                            String desc = classMap.get(name.equals("<init>") ? enumClassName.substring(enumClassName.lastIndexOf('.') + 1) : name);
                            if (desc == null && name.equals("<init>")) desc = classMap.get("<init>");
                            if (desc != null) methodJavadoc = desc;
                        }
                    }
                } catch (Exception ignored) {}
                methodInfo.put(StringUtils.fromString("javadoc"), methodJavadoc == null ? null : StringUtils.fromString(methodJavadoc));
                
                // Basic parameter extraction from descriptor
                String[] paramTypes = extractParameterTypesFromDescriptor(descriptor);
                List<BMap<BString, Object>> params = new ArrayList<>();
                for (int i = 0; i < paramTypes.length; i++) {
                    BMap<BString, Object> paramInfo = ValueCreator.createMapValue(mapType);
                    paramInfo.put(StringUtils.fromString("name"), StringUtils.fromString("arg" + i));
                    paramInfo.put(StringUtils.fromString("type"), StringUtils.fromString(paramTypes[i]));
                    paramInfo.put(StringUtils.fromString("isVarArgs"), false);
                    params.add(paramInfo);
                }
                methodInfo.put(StringUtils.fromString("parameters"),
                        ValueCreator.createArrayValue(params.toArray(BMap[]::new), 
                        TypeCreator.createArrayType(mapType)));
                
                // Exceptions
                BString[] exceptionNames = new BString[exceptions == null ? 0 : exceptions.length];
                if (exceptions != null) {
                    for (int i = 0; i < exceptions.length; i++) {
                        exceptionNames[i] = StringUtils.fromString(exceptions[i].replace('/', '.'));
                    }
                }
                methodInfo.put(StringUtils.fromString("exceptions"), ValueCreator.createArrayValue(exceptionNames));
                
                if (name.equals("<init>")) {
                    constructors.add(methodInfo);
                } else {
                    methods.add(methodInfo);
                }
            }
            
            return null;
        }
        
        @Override
        public void visitEnd() {
            for (Map.Entry<String, BMap<BString, Object>> entry : pendingConstantHolderFields.entrySet()) {
                String fieldName = entry.getKey();
                BMap<BString, Object> fieldInfo = entry.getValue();
                String actualValue = constantHolderStringValues.get(fieldName);
                if (actualValue != null) {
                    fieldInfo.put(StringUtils.fromString("literalValue"),
                            StringUtils.fromString(actualValue));
                }
                fields.add(fieldInfo);
            }

            // Set collected methods, fields, constructors
            classInfo.put(StringUtils.fromString("methods"),
                    ValueCreator.createArrayValue(methods.toArray(BMap[]::new), 
                    TypeCreator.createArrayType(mapType)));
            classInfo.put(StringUtils.fromString("fields"),
                    ValueCreator.createArrayValue(fields.toArray(BMap[]::new), 
                    TypeCreator.createArrayType(mapType)));
            classInfo.put(StringUtils.fromString("constructors"),
                    ValueCreator.createArrayValue(constructors.toArray(BMap[]::new), 
                    TypeCreator.createArrayType(mapType)));
            
            // Default values
            classInfo.put(StringUtils.fromString("isDeprecated"), false);
            classInfo.put(StringUtils.fromString("annotations"), ValueCreator.createArrayValue(new BString[0]));
        }
        
        private String extractReturnTypeFromDescriptor(String descriptor) {
            int returnStart = descriptor.indexOf(')') + 1;
            return descriptorToClassName(descriptor.substring(returnStart));
        }
        
        /**
         * Extract return type from generic signature (preserves generic type parameters).
         * Signature format: ()Ljava/util/List<Lsoftware/amazon/awssdk/services/s3/model/Tag;>;
         * Returns: java.util.List<software.amazon.awssdk.services.s3.model.Tag>
         */
        private String extractReturnTypeFromSignature(String signature) {
            int returnStart = signature.indexOf(')') + 1;
            String returnPart = signature.substring(returnStart);
            return signatureToTypeName(returnPart);
        }
        
        /**
         * Convert a generic signature to a readable type name.
         * Handles nested generics like Map<String, List<Tag>>
         */
        private String signatureToTypeName(String sig) {
            if (sig == null || sig.isEmpty()) {
                return sig;
            }
            
            // Handle primitive types
            if (sig.length() == 1) {
                switch (sig.charAt(0)) {
                    case 'V' -> {
                        return "void";
                    }
                    case 'Z' -> {
                        return "boolean";
                    }
                    case 'B' -> {
                        return "byte";
                    }
                    case 'C' -> {
                        return "char";
                    }
                    case 'S' -> {
                        return "short";
                    }
                    case 'I' -> {
                        return "int";
                    }
                    case 'J' -> {
                        return "long";
                    }
                    case 'F' -> {
                        return "float";
                    }
                    case 'D' -> {
                        return "double";
                    }
                }
            }
            
            // Handle array types
            if (sig.startsWith("[")) {
                return signatureToTypeName(sig.substring(1)) + "[]";
            }
            
            // Handle object types (L...;)
            if (sig.startsWith("L")) {
                // Find the end - need to handle nested <> properly
                int depth = 0;
                int end = 1;
                while (end < sig.length()) {
                    char c = sig.charAt(end);
                    if (c == '<') depth++;
                    else if (c == '>') depth--;
                    else if (c == ';' && depth == 0) break;
                    end++;
                }
                
                String inner = sig.substring(1, end);
                
                // Check for generic parameters
                int genericStart = inner.indexOf('<');
                if (genericStart >= 0) {
                    String baseType = inner.substring(0, genericStart).replace('/', '.');
                    String genericPart = inner.substring(genericStart);
                    String parsedGenerics = parseGenericPart(genericPart);
                    return baseType + parsedGenerics;
                } else {
                    return inner.replace('/', '.');
                }
            }
            
            // Handle type variables (e.g., T)
            if (sig.startsWith("T")) {
                int end = sig.indexOf(';');
                if (end > 0) {
                    return sig.substring(1, end);
                }
            }
            
            return sig.replace('/', '.');
        }
        
        /**
         * Parse generic part of a signature like <Ljava/lang/String;Ljava/util/List<Ljava/lang/Integer;>;>
         * Returns: <java.lang.String, java.util.List<java.lang.Integer>>
         */
        private String parseGenericPart(String genericPart) {
            if (!genericPart.startsWith("<") || !genericPart.endsWith(">")) {
                return genericPart;
            }
            
            String inner = genericPart.substring(1, genericPart.length() - 1);
            StringBuilder result = new StringBuilder("<");
            
            int i = 0;
            boolean first = true;
            while (i < inner.length()) {
                if (!first) {
                    result.append(", ");
                }
                first = false;
                
                char c = inner.charAt(i);
                
                // Handle wildcards
                if (c == '+' || c == '-') {
                    i++;
                    c = inner.charAt(i);
                }
                
                switch (c) {
                    case '*' -> {
                        result.append("?");
                        i++;
                    }
                    case 'L' -> {
                            int depth = 0;
                            int end = i + 1;
                            while (end < inner.length()) {
                                char ec = inner.charAt(end);
                                if (ec == '<') depth++;
                                else if (ec == '>') depth--;
                                else if (ec == ';' && depth == 0) break;
                                end++;
                            }       String typeStr = inner.substring(i, end + 1);
                            result.append(signatureToTypeName(typeStr));
                            i = end + 1;
                    }
                    case 'T' -> {
                            // Type variable
                            int end = inner.indexOf(';', i);
                            result.append(inner.substring(i + 1, end));
                            i = end + 1;
                    }
                    default -> {
                        // Primitive type
                        result.append(signatureToTypeName(String.valueOf(c)));
                        i++;
                    }
                }
            }
            
            result.append(">");
            return result.toString();
        }
        
        private String[] extractParameterTypesFromDescriptor(String descriptor) {
            String params = descriptor.substring(1, descriptor.indexOf(')'));
            List<String> types = new ArrayList<>();
            
            int i = 0;
            while (i < params.length()) {
                char c = params.charAt(i);
                switch (c) {
                    case 'L' -> {
                        int end = params.indexOf(';', i);
                        types.add(descriptorToClassName(params.substring(i, end + 1)));
                        i = end + 1;
                    }
                    case '[' -> {
                        int start = i;
                        while (i < params.length() && params.charAt(i) == '[') {
                            i++;
                        }   if (i < params.length()) {
                            if (params.charAt(i) == 'L') {
                                int end = params.indexOf(';', i);
                                types.add(descriptorToClassName(params.substring(start, end + 1)));
                                i = end + 1;
                            } else {
                                types.add(descriptorToClassName(params.substring(start, i + 1)));
                                i++;
                            }
                        }
                    }
                    default -> {
                        types.add(descriptorToClassName(String.valueOf(c)));
                        i++;
                    }
                }
            }
            
            return types.toArray(String[]::new);
        }
        
        private String descriptorToClassName(String descriptor) {
            switch (descriptor) {
                case "V" -> {
                    return "void";
                }
                case "Z" -> {
                    return "boolean";
                }
                case "B" -> {
                    return "byte";
                }
                case "C" -> {
                    return "char";
                }
                case "S" -> {
                    return "short";
                }
                case "I" -> {
                    return "int";
                }
                case "J" -> {
                    return "long";
                }
                case "F" -> {
                    return "float";
                }
                case "D" -> {
                    return "double";
                }
                default -> {
                    if (descriptor.startsWith("L") && descriptor.endsWith(";")) {
                        return descriptor.substring(1, descriptor.length() - 1).replace('/', '.');
                    } else if (descriptor.startsWith("[")) {
                        return descriptorToClassName(descriptor.substring(1)) + "[]";
                    }
                    return descriptor;
                }
            }
        }
    }

    /**
     * MethodVisitor for a class static initializer.
     *
     * This is the standard constant-holder pattern where a final class exposes a fixed
     * set of named instances created through a string factory method.  The pattern is
     * generic and not tied to any particular SDK or vendor.
     */
    private static class ConstantHolderInitVisitor extends MethodVisitor {

        private final String classInternalName; // e.g. "software/amazon/awssdk/regions/Region"
        private final Map<String, String> result;
        private String pendingString = null;   // last LDC string seen

        ConstantHolderInitVisitor(String className, Map<String, String> result) {
            super(Opcodes.ASM9);
            this.classInternalName = className.replace('.', '/');
            this.result = result;
        }

        @Override
        public void visitLdcInsn(Object value) {
            // Record string constants; reset on non-string LDC
            pendingString = (value instanceof String) ? (String) value : null;
        }

        @Override
        public void visitMethodInsn(int opcode, String owner, String name,
                String descriptor, boolean isInterface) {
            if (opcode != Opcodes.INVOKESTATIC || !owner.equals(classInternalName)) {
                pendingString = null;
            }
        }

        @Override
        public void visitFieldInsn(int opcode, String owner, String name, String descriptor) {
            if (opcode == Opcodes.PUTSTATIC
                    && owner.equals(classInternalName)
                    && pendingString != null) {
                result.put(name, pendingString);
            }
            pendingString = null;
        }

        @Override public void visitInsn(int opcode) {}
        @Override public void visitIntInsn(int opcode, int operand) {}
        @Override public void visitVarInsn(int opcode, int var) {}
        @Override public void visitTypeInsn(int opcode, String type) {}
    }

    // Overload to accept Ballerina BString
    public static Object analyzeJarWithJavaParser(BString jarPath) {
        if (jarPath == null) {
            return null;
        }
        return analyzeJarWithJavaParser(jarPath.getValue());
    }

    /**
     * Extract filtered javadoc for specific classes and members.
     * This is more efficient than loading all javadoc entries when you only need specific ones.
     *
     * @param javadocPath Path to the javadoc JAR file
     * @param classNames Array of fully-qualified class names to extract
     * @param memberNames Array of member names to extract (optional; if null/empty, extract all)
     * @return JSON map of class FQNs to member descriptions
     */
    public static Object extractFilteredJavadoc(BString javadocPath, BArray classNames, BArray memberNames) {
        try {
            if (javadocPath == null || javadocPath.getValue().isEmpty()) {
                return ValueCreator.createMapValue(TypeCreator.createMapType(PredefinedTypes.TYPE_STRING));
            }

            File javadocJar = new File(javadocPath.getValue());
            if (!javadocJar.exists()) {
                System.err.println("WARNING: extractFilteredJavadoc: javadoc JAR not found: " + javadocJar.getAbsolutePath());
                return ValueCreator.createMapValue(TypeCreator.createMapType(PredefinedTypes.TYPE_STRING));
            }

            // Convert BArray to Set<String>
            Set<String> targetClasses = new java.util.HashSet<>();
            if (classNames != null) {
                for (int i = 0; i < classNames.getLength(); i++) {
                    String cn = classNames.getBString(i).getValue();
                    if (cn != null && !cn.isEmpty()) {
                        targetClasses.add(cn);
                    }
                }
            }

            Set<String> targetMembers = new java.util.HashSet<>();
            if (memberNames != null) {
                for (int i = 0; i < memberNames.getLength(); i++) {
                    String mn = memberNames.getBString(i).getValue();
                    if (mn != null && !mn.isEmpty()) {
                        targetMembers.add(mn);
                    }
                }
            }

            logInfo("extractFilteredJavadoc: loading javadoc for " + targetClasses.size() + " classes and " + targetMembers.size() + " member names");

            // Use the filtered loading method
            Map<String, Map<String, String>> filteredJavadoc = JavadocExtractor.loadFilteredFromJar(
                    javadocJar,
                    targetClasses,
                    targetMembers.isEmpty() ? null : targetMembers
            );

            // Convert to Ballerina map<string|map<string>>
            BMap<BString, Object> resultMap = ValueCreator.createMapValue(TypeCreator.createMapType(PredefinedTypes.TYPE_JSON));
            
            for (String className : filteredJavadoc.keySet()) {
                Map<String, String> memberDescs = filteredJavadoc.get(className);
                BMap<BString, Object> memberMap = ValueCreator.createMapValue(TypeCreator.createMapType(PredefinedTypes.TYPE_STRING));
                
                for (String memberName : memberDescs.keySet()) {
                    String description = memberDescs.get(memberName);
                    memberMap.put(StringUtils.fromString(memberName), StringUtils.fromString(description));
                }
                
                resultMap.put(StringUtils.fromString(className), memberMap);
            }

            logInfo("extractFilteredJavadoc: extracted javadoc for " + filteredJavadoc.size() + " classes");
            return resultMap;

        } catch (Exception e) {
            System.err.println("ERROR: extractFilteredJavadoc failed: " + e.getMessage());
            return ValueCreator.createMapValue(TypeCreator.createMapType(PredefinedTypes.TYPE_STRING));
        }
    }
}