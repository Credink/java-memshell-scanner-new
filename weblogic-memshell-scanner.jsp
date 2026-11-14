<%@ page import="java.io.*" %>
<%@ page import="java.lang.reflect.Array" %>
<%@ page import="java.lang.reflect.Field" %>
<%@ page import="java.lang.reflect.Method" %>
<%@ page import="java.net.URL" %>
<%@ page import="java.net.URLEncoder" %>
<%@ page import="java.text.SimpleDateFormat" %>
<%@ page import="java.util.*" %>
<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%!
    public static final String VERSION = "0.1.0";

    public static boolean openAccess(Object accessible) {
        if (accessible == null) {
            return false;
        }
        try {
            Method trySet = accessible.getClass().getMethod("trySetAccessible");
            if (Boolean.TRUE.equals(trySet.invoke(accessible))) {
                return true;
            }
        } catch (Throwable ignored) {
        }
        try {
            Method setAcc = accessible.getClass().getMethod("setAccessible", boolean.class);
            setAcc.invoke(accessible, Boolean.TRUE);
            return true;
        } catch (Throwable ignored) {
            return false;
        }
    }

    public static Field findField(Class<?> clazz, String name) {
        Class<?> c = clazz;
        while (c != null && c != Object.class) {
            try {
                Field f = c.getDeclaredField(name);
                openAccess(f);
                return f;
            } catch (NoSuchFieldException ignored) {
                c = c.getSuperclass();
            }
        }
        return null;
    }

    public static Object getFieldValue(Object obj, String name) throws Exception {
        if (obj == null) {
            throw new IllegalArgumentException("null object for field " + name);
        }
        Field f = findField(obj.getClass(), name);
        if (f == null) {
            throw new NoSuchFieldException(obj.getClass().getName() + "." + name);
        }
        return f.get(obj);
    }

    public static Method findCompatibleMethod(Class<?> clazz, String name, Object... args) {
        if (clazz == null) {
            return null;
        }
        int argc = args == null ? 0 : args.length;
        List<Method> candidates = new ArrayList<Method>();
        Class<?> c = clazz;
        while (c != null && c != Object.class) {
            Method[] ms = c.getDeclaredMethods();
            for (int i = 0; i < ms.length; i++) {
                if (name.equals(ms[i].getName()) && ms[i].getParameterTypes().length == argc) {
                    candidates.add(ms[i]);
                }
            }
            c = c.getSuperclass();
        }
        try {
            Method[] pubs = clazz.getMethods();
            for (int i = 0; i < pubs.length; i++) {
                if (name.equals(pubs[i].getName()) && pubs[i].getParameterTypes().length == argc) {
                    candidates.add(pubs[i]);
                }
            }
        } catch (Throwable ignored) {
        }
        for (Method m : candidates) {
            Class<?>[] pts = m.getParameterTypes();
            boolean ok = true;
            for (int i = 0; i < argc; i++) {
                if (args[i] == null) {
                    if (pts[i].isPrimitive()) {
                        ok = false;
                        break;
                    }
                    continue;
                }
                Class<?> expect = pts[i].isPrimitive() ? wrapPrimitive(pts[i]) : pts[i];
                if (!expect.isAssignableFrom(args[i].getClass()) && !pts[i].isInstance(args[i])) {
                    ok = false;
                    break;
                }
            }
            if (ok) {
                openAccess(m);
                return m;
            }
        }
        return null;
    }

    public static Class<?> wrapPrimitive(Class<?> t) {
        if (t == int.class) return Integer.class;
        if (t == long.class) return Long.class;
        if (t == boolean.class) return Boolean.class;
        if (t == byte.class) return Byte.class;
        if (t == short.class) return Short.class;
        if (t == char.class) return Character.class;
        if (t == float.class) return Float.class;
        if (t == double.class) return Double.class;
        return t;
    }

    public static Object invokeName(Object obj, String method, Object... args) throws Exception {
        Method m = findCompatibleMethod(obj.getClass(), method, args);
        if (m == null) {
            throw new NoSuchMethodException(obj.getClass().getName() + "." + method);
        }
        return m.invoke(obj, args);
    }

    public static Class<?> tryClass(String... names) {
        ClassLoader ctx = Thread.currentThread().getContextClassLoader();
        for (int i = 0; i < names.length; i++) {
            try {
                if (ctx != null) {
                    return Class.forName(names[i], false, ctx);
                }
            } catch (Throwable ignored) {
            }
            try {
                return Class.forName(names[i]);
            } catch (Throwable ignored) {
            }
        }
        return null;
    }

    public static Class<?> loadClassFlexible(String className) throws ClassNotFoundException {
        ClassLoader[] loaders = new ClassLoader[]{
                Thread.currentThread().getContextClassLoader(),
                WlsScannerBootstrap.class.getClassLoader(),
                ClassLoader.getSystemClassLoader()
        };
        for (int i = 0; i < loaders.length; i++) {
            if (loaders[i] == null) {
                continue;
            }
            try {
                return Class.forName(className, false, loaders[i]);
            } catch (ClassNotFoundException ignored) {
            }
        }
        return Class.forName(className);
    }

    public static class WlsScannerBootstrap {
    }

    public static String html(Object o) {
        if (o == null) {
            return "";
        }
        return String.valueOf(o)
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;");
    }

    public static void writeOut(Object out, String s) throws Exception {
        if (out instanceof Writer) {
            ((Writer) out).write(s);
            return;
        }
        invokeName(out, "write", s);
    }

    public static String classLoaderName(Class<?> clazz) {
        if (clazz == null) {
            return "null";
        }
        ClassLoader cl = clazz.getClassLoader();
        if (cl == null) {
            return "Bootstrap ClassLoader";
        }
        return cl.getClass().getName() + "@" + Integer.toHexString(System.identityHashCode(cl));
    }

    public static String classFilePath(Class<?> clazz) {
        if (clazz == null) {
            return "class is null";
        }
        try {
            ClassLoader cl = clazz.getClassLoader();
            String path = clazz.getName().replace('.', '/') + ".class";
            URL url = cl == null ? ClassLoader.getSystemResource(path) : cl.getResource(path);
            if (url == null) {
                return "磁盘无对应 class，疑似内存马";
            }
            return url.getPath();
        } catch (Exception e) {
            return "检测失败: " + e.getMessage();
        }
    }

    public static String judgeClassLocation(Class<?> clazz) {
        try {
            if (clazz == null) {
                return "无法判断";
            }
            ClassLoader cl = clazz.getClassLoader();
            String path = clazz.getName().replace('.', '/') + ".class";
            URL url = cl == null ? ClassLoader.getSystemResource(path) : cl.getResource(path);
            if (url == null) {
                return "<span style=\"color:#c0392b;font-weight:bold\">磁盘无 class：高度可疑</span>";
            }
            String urlStr = url.toString();
            if (urlStr.contains(".jar!")) {
                String jarPath = urlStr.substring(0, urlStr.indexOf('!')).replaceFirst("^jar:file:", "");
                File jarFile = new File(jarPath);
                String time = jarFile.exists()
                        ? new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new Date(jarFile.lastModified()))
                        : "unknown";
                return "来自依赖 jar，mtime=" + time;
            }
            if (urlStr.contains("/WEB-INF/classes/") || urlStr.contains("/classes/")) {
                return "来自 WEB-INF/classes 或展开目录";
            }
            if (urlStr.contains("/_WL_internal/") || urlStr.contains("/tmp/_WL_user/")) {
                return "来自 WebLogic 临时/内部目录";
            }
            return "已找到 class 资源";
        } catch (Exception e) {
            return "无法判断";
        }
    }

    public static boolean isWebAppServletContext(Object o) {
        if (o == null) {
            return false;
        }
        String n = o.getClass().getName();
        return n.contains("WebAppServletContext")
                || tryClass("weblogic.servlet.internal.WebAppServletContext") != null
                && tryClass("weblogic.servlet.internal.WebAppServletContext").isInstance(o);
    }

    /**
     * 多路径获取当前请求对应的 WebAppServletContext，兼容包装器与版本字段差异。
     */
    public static Object getWebAppServletContext(HttpServletRequest request) throws Exception {
        Exception last = null;

        // 1) request / ServletRequestImpl.context
        try {
            Object cur = request;
            for (int i = 0; i < 10 && cur != null; i++) {
                if (isWebAppServletContext(cur)) {
                    return cur;
                }
                Object ctx = null;
                try {
                    ctx = getFieldValue(cur, "context");
                } catch (Exception ignored) {
                }
                if (isWebAppServletContext(ctx)) {
                    return ctx;
                }
                Object next = null;
                try {
                    next = getFieldValue(cur, "request");
                } catch (Exception ignored) {
                }
                if (next == null) {
                    try {
                        next = invokeName(cur, "getRequest");
                    } catch (Exception ignored) {
                    }
                }
                // ServletRequestImpl.getOriginalRequest
                if (next == null) {
                    try {
                        Method m = findCompatibleMethod(tryClass("weblogic.servlet.internal.ServletRequestImpl"),
                                "getOriginalRequest", cur);
                        if (m != null) {
                            next = m.invoke(null, cur);
                        }
                    } catch (Exception ignored) {
                    }
                }
                if (next == null || next == cur) {
                    break;
                }
                cur = next;
            }
        } catch (Exception e) {
            last = e;
        }

        // 2) ServletContext 自身或内部字段
        try {
            Object sc = null;
            Method m = findCompatibleMethod(request.getClass(), "getServletContext");
            if (m != null) {
                sc = m.invoke(request);
            }
            if (sc == null) {
                Object session = invokeName(request, "getSession", Boolean.FALSE);
                if (session == null) {
                    session = invokeName(request, "getSession", Boolean.TRUE);
                }
                if (session != null) {
                    sc = invokeName(session, "getServletContext");
                }
            }
            if (isWebAppServletContext(sc)) {
                return sc;
            }
            if (sc != null) {
                Object nested = null;
                try {
                    nested = getFieldValue(sc, "context");
                } catch (Exception ignored) {
                }
                if (isWebAppServletContext(nested)) {
                    return nested;
                }
            }
        } catch (Exception e) {
            last = e;
        }

        // 3) 线程 workEntry 回退（部分异步/非标准入口）
        try {
            Object fromThread = findContextFromCurrentThread();
            if (isWebAppServletContext(fromThread)) {
                return fromThread;
            }
        } catch (Exception e) {
            last = e;
        }

        throw last != null ? last : new IllegalStateException("无法获取 WebAppServletContext（确认部署在 WebLogic）");
    }

    public static Object findContextFromCurrentThread() {
        try {
            Thread t = Thread.currentThread();
            Object workEntry = null;
            try {
                workEntry = getFieldValue(t, "workEntry");
            } catch (Exception ignored) {
            }
            if (workEntry == null) {
                return null;
            }
            try {
                Object ch = getFieldValue(workEntry, "connectionHandler");
                if (ch != null) {
                    Object req = getFieldValue(ch, "request");
                    if (req != null) {
                        Object ctx = getFieldValue(req, "context");
                        if (isWebAppServletContext(ctx)) {
                            return ctx;
                        }
                    }
                }
            } catch (Exception ignored) {
            }
            try {
                Object ctx = getFieldValue(workEntry, "context");
                if (isWebAppServletContext(ctx)) {
                    return ctx;
                }
            } catch (Exception ignored) {
            }
        } catch (Exception ignored) {
        }
        return null;
    }

    public static String detectWebLogicInfo(Object context) {
        String ver = null;
        try {
            Class<?> v = tryClass("weblogic.version");
            if (v != null) {
                Method getRelease = findCompatibleMethod(v, "getReleaseBuildVersion");
                if (getRelease != null) {
                    ver = String.valueOf(getRelease.invoke(null));
                }
            }
        } catch (Exception ignored) {
        }
        if (ver == null) {
            try {
                Package p = context.getClass().getPackage();
                if (p != null && p.getImplementationVersion() != null) {
                    ver = p.getImplementationVersion();
                }
            } catch (Exception ignored) {
            }
        }
        String name = "-";
        try {
            Object n = invokeName(context, "getName");
            if (n != null) {
                name = String.valueOf(n);
            }
        } catch (Exception ignored) {
        }
        try {
            Object n = invokeName(context, "getContextPath");
            if (n != null) {
                name = name + " path=" + n;
            }
        } catch (Exception ignored) {
        }
        return "WebLogic " + (ver == null ? "unknown" : ver) + " | context=" + name;
    }

    public static Object getFilterManager(Object context) throws Exception {
        try {
            return invokeName(context, "getFilterManager");
        } catch (Exception e) {
            return getFieldValue(context, "filterManager");
        }
    }

    public static Object getEventsManager(Object context) throws Exception {
        try {
            return getFieldValue(context, "eventsManager");
        } catch (Exception e) {
            return invokeName(context, "getEventsManager");
        }
    }

    public static Map<?, ?> asMap(Object o) {
        if (o instanceof Map) {
            return (Map<?, ?>) o;
        }
        return Collections.emptyMap();
    }

    public static List<?> asList(Object o) {
        if (o instanceof List) {
            return (List<?>) o;
        }
        if (o != null && o.getClass().isArray()) {
            int n = Array.getLength(o);
            List<Object> list = new ArrayList<Object>(n);
            for (int i = 0; i < n; i++) {
                list.add(Array.get(o, i));
            }
            return list;
        }
        return Collections.emptyList();
    }

    public static class FilterInfo {
        public String filterName;
        public String className;
        public Class<?> clazz;
        public String patterns;
        public Object wrapper;
    }

    public static class ServletInfo {
        public String servletName;
        public String className;
        public Class<?> clazz;
        public String patterns;
        public Object stub;
    }

    public static class ListenerInfo {
        public String kind;
        public Class<?> clazz;
        public Object listener;
    }

    public static List<FilterInfo> scanFilters(Object context) throws Exception {
        List<FilterInfo> result = new ArrayList<FilterInfo>();
        Object fm = getFilterManager(context);
        Map<?, ?> filters = asMap(getFieldValue(fm, "filters"));
        Map<String, String> patternByName = new HashMap<String, String>();
        try {
            List<?> patternList = asList(getFieldValue(fm, "filterPatternList"));
            for (Object pi : patternList) {
                String fname = null;
                try {
                    fname = String.valueOf(getFieldValue(pi, "filterName"));
                } catch (Exception ignored) {
                }
                String patterns = extractFilterPatterns(pi);
                if (fname != null) {
                    String old = patternByName.get(fname);
                    patternByName.put(fname, old == null ? patterns : old + "," + patterns);
                }
            }
        } catch (Exception ignored) {
        }

        for (Map.Entry<?, ?> e : filters.entrySet()) {
            FilterInfo info = new FilterInfo();
            info.filterName = String.valueOf(e.getKey());
            info.wrapper = e.getValue();
            info.patterns = patternByName.containsKey(info.filterName)
                    ? patternByName.get(info.filterName) : "-";
            try {
                Object filter = getFieldValue(info.wrapper, "filter");
                if (filter != null) {
                    info.clazz = filter.getClass();
                    info.className = info.clazz.getName();
                }
            } catch (Exception ignored) {
            }
            if (info.className == null) {
                try {
                    Object cn = getFieldValue(info.wrapper, "filterClassName");
                    info.className = cn == null ? "-" : String.valueOf(cn);
                    if (cn != null) {
                        try {
                            info.clazz = loadClassFlexible(info.className);
                        } catch (Exception ignored) {
                        }
                    }
                } catch (Exception ignored) {
                    info.className = "-";
                }
            }
            result.add(info);
        }
        return result;
    }

    public static String extractFilterPatterns(Object filterPatternInfo) {
        try {
            Object map = getFieldValue(filterPatternInfo, "map");
            if (map != null) {
                // ServletMapping / URLMapping：尽量 toString 或读 matchMap keys
                try {
                    Object matchMap = getFieldValue(map, "matchMap");
                    if (matchMap instanceof Map) {
                        return String.valueOf(((Map<?, ?>) matchMap).keySet());
                    }
                } catch (Exception ignored) {
                }
                return String.valueOf(map);
            }
        } catch (Exception ignored) {
        }
        try {
            Object url = getFieldValue(filterPatternInfo, "urlPattern");
            if (url != null) {
                return String.valueOf(url);
            }
        } catch (Exception ignored) {
        }
        return "-";
    }

    public static List<ServletInfo> scanServlets(Object context) throws Exception {
        List<ServletInfo> result = new ArrayList<ServletInfo>();
        Map<?, ?> stubs = Collections.emptyMap();
        try {
            stubs = asMap(getFieldValue(context, "servletStubs"));
        } catch (Exception ignored) {
        }
        if (stubs.isEmpty()) {
            try {
                Object m = invokeName(context, "getServletStubs");
                stubs = asMap(m);
            } catch (Exception ignored) {
            }
        }

        Map<String, String> patternsByStubName = new HashMap<String, String>();
        try {
            Object servletMapping = null;
            try {
                servletMapping = invokeName(context, "getServletMapping");
            } catch (Exception ignored) {
            }
            if (servletMapping == null) {
                servletMapping = getFieldValue(context, "servletMapping");
            }
            collectServletPatterns(servletMapping, patternsByStubName);
        } catch (Exception ignored) {
        }

        for (Map.Entry<?, ?> e : stubs.entrySet()) {
            ServletInfo info = new ServletInfo();
            info.servletName = String.valueOf(e.getKey());
            info.stub = e.getValue();
            info.patterns = patternsByStubName.containsKey(info.servletName)
                    ? patternsByStubName.get(info.servletName) : "-";
            try {
                Object cn = getFieldValue(info.stub, "className");
                if (cn == null) {
                    cn = invokeName(info.stub, "getClassName");
                }
                info.className = cn == null ? "-" : String.valueOf(cn);
            } catch (Exception ex) {
                info.className = "-";
            }
            try {
                Object servlet = null;
                try {
                    servlet = getFieldValue(info.stub, "servlet");
                } catch (Exception ignored) {
                }
                if (servlet == null) {
                    try {
                        servlet = invokeName(info.stub, "getServlet");
                    } catch (Exception ignored) {
                    }
                }
                if (servlet != null) {
                    info.clazz = servlet.getClass();
                    info.className = info.clazz.getName();
                } else if (info.className != null && !"-".equals(info.className)) {
                    try {
                        info.clazz = loadClassFlexible(info.className);
                    } catch (Exception ignored) {
                    }
                }
            } catch (Exception ignored) {
            }
            result.add(info);
        }
        return result;
    }

    public static void collectServletPatterns(Object mappingNode, Map<String, String> out) {
        if (mappingNode == null) {
            return;
        }
        // StandardURLMapping: matchMap / extensionMap
        for (String field : new String[]{"matchMap", "extensionMap", "pathMap", "defaultMap"}) {
            try {
                Object mapObj = getFieldValue(mappingNode, field);
                if (!(mapObj instanceof Map)) {
                    continue;
                }
                Map<?, ?> map = (Map<?, ?>) mapObj;
                for (Map.Entry<?, ?> e : map.entrySet()) {
                    String pattern = String.valueOf(e.getKey());
                    String servletName = resolveServletNameFromMappingValue(e.getValue());
                    if (servletName != null) {
                        String old = out.get(servletName);
                        out.put(servletName, old == null ? pattern : old + "," + pattern);
                    }
                }
            } catch (Exception ignored) {
            }
        }
        // 某些版本 URLMapping 自身是 Map
        if (mappingNode instanceof Map) {
            Map<?, ?> map = (Map<?, ?>) mappingNode;
            for (Map.Entry<?, ?> e : map.entrySet()) {
                String pattern = String.valueOf(e.getKey());
                String servletName = resolveServletNameFromMappingValue(e.getValue());
                if (servletName != null) {
                    String old = out.get(servletName);
                    out.put(servletName, old == null ? pattern : old + "," + pattern);
                }
            }
        }
    }

    public static String resolveServletNameFromMappingValue(Object value) {
        if (value == null) {
            return null;
        }
        Object cur = value;
        for (int depth = 0; depth < 6 && cur != null; depth++) {
            try {
                Object stub = null;
                try {
                    stub = getFieldValue(cur, "servletStub");
                } catch (Exception ignored) {
                }
                if (stub == null) {
                    try {
                        stub = getFieldValue(cur, "exactValue");
                        if (stub != null) {
                            Object s2 = null;
                            try {
                                s2 = getFieldValue(stub, "servletStub");
                            } catch (Exception ignored) {
                            }
                            if (s2 != null) {
                                stub = s2;
                            } else {
                                // URLMatchHelper
                                try {
                                    Object s3 = getFieldValue(stub, "servletStub");
                                    if (s3 != null) {
                                        stub = s3;
                                    }
                                } catch (Exception ignored) {
                                }
                            }
                        }
                    } catch (Exception ignored) {
                    }
                }
                if (stub != null) {
                    try {
                        Object name = getFieldValue(stub, "name");
                        if (name != null) {
                            return String.valueOf(name);
                        }
                    } catch (Exception ignored) {
                    }
                    try {
                        Object name = invokeName(stub, "getName");
                        if (name != null) {
                            return String.valueOf(name);
                        }
                    } catch (Exception ignored) {
                    }
                }
            } catch (Exception ignored) {
            }
            // descend exactValue / value
            Object next = null;
            try {
                next = getFieldValue(cur, "exactValue");
            } catch (Exception ignored) {
            }
            if (next == null) {
                try {
                    next = getFieldValue(cur, "value");
                } catch (Exception ignored) {
                }
            }
            if (next == null || next == cur) {
                break;
            }
            cur = next;
        }
        return null;
    }

    public static List<ListenerInfo> scanListeners(Object context) throws Exception {
        List<ListenerInfo> result = new ArrayList<ListenerInfo>();
        Object events = getEventsManager(context);
        String[][] fields = new String[][]{
                {"requestListeners", "ServletRequestListener"},
                {"ctxListeners", "ServletContextListener"},
                {"sessionListeners", "HttpSessionListener"},
                {"sessionIdListeners", "HttpSessionIdListener"},
                {"contextAttributeListeners", "ServletContextAttributeListener"},
                {"requestAttributeListeners", "ServletRequestAttributeListener"},
                {"sessionAttributeListeners", "HttpSessionAttributeListener"},
                {"sessionActivationListeners", "HttpSessionActivationListener"},
                {"sessionBindingListeners", "HttpSessionBindingListener"}
        };
        Set<Integer> seen = new HashSet<Integer>();
        for (int i = 0; i < fields.length; i++) {
            Object val = null;
            try {
                val = getFieldValue(events, fields[i][0]);
            } catch (Exception ignored) {
                continue;
            }
            for (Object o : asList(val)) {
                if (o == null) {
                    continue;
                }
                int id = System.identityHashCode(o);
                if (!seen.add(Integer.valueOf(id))) {
                    continue;
                }
                ListenerInfo info = new ListenerInfo();
                info.kind = fields[i][1];
                info.listener = o;
                info.clazz = o.getClass();
                result.add(info);
            }
        }
        return result;
    }

    public static List<Class<?>> scanCachedClasses(Object context) throws Exception {
        List<Class<?>> suspicious = new ArrayList<Class<?>>();
        ClassLoader cl = null;
        try {
            cl = (ClassLoader) invokeName(context, "getServletClassLoader");
        } catch (Exception ignored) {
        }
        if (cl == null) {
            try {
                cl = (ClassLoader) invokeName(context, "getClassLoader");
            } catch (Exception ignored) {
            }
        }
        if (cl == null) {
            try {
                cl = (ClassLoader) getFieldValue(context, "classLoader");
            } catch (Exception ignored) {
            }
        }
        if (cl == null) {
            return suspicious;
        }
        Object cached = null;
        Class<?> c = cl.getClass();
        while (c != null && c != Object.class && cached == null) {
            try {
                cached = getFieldValue(cl, "cachedClasses");
            } catch (Exception ignored) {
                c = c.getSuperclass();
            }
        }
        if (!(cached instanceof Map)) {
            return suspicious;
        }
        Map<?, ?> map = (Map<?, ?>) cached;
        for (Object v : map.values()) {
            if (!(v instanceof Class)) {
                continue;
            }
            Class<?> clazz = (Class<?>) v;
            // 无磁盘 class 的动态类优先展示
            if ("磁盘无对应 class，疑似内存马".equals(classFilePath(clazz))) {
                suspicious.add(clazz);
            }
        }
        return suspicious;
    }

    public static synchronized void deleteFilter(Object context, String filterName) throws Exception {
        Object fm = getFilterManager(context);
        Map<?, ?> filters = asMap(getFieldValue(fm, "filters"));
        Object wrapper = filters.get(filterName);
        if (wrapper == null) {
            throw new IllegalArgumentException("Filter 不存在: " + filterName);
        }
        String className = null;
        try {
            Object filter = getFieldValue(wrapper, "filter");
            if (filter != null) {
                className = filter.getClass().getName();
                try {
                    invokeName(filter, "destroy");
                } catch (Exception ignored) {
                }
            }
        } catch (Exception ignored) {
        }
        if (className == null) {
            try {
                Object cn = getFieldValue(wrapper, "filterClassName");
                if (cn != null) {
                    className = String.valueOf(cn);
                }
            } catch (Exception ignored) {
            }
        }
        // 删 mapping
        try {
            List<?> patternList = asList(getFieldValue(fm, "filterPatternList"));
            // 需要可变 List
            Field f = findField(fm.getClass(), "filterPatternList");
            Object raw = f.get(fm);
            if (raw instanceof List) {
                @SuppressWarnings("unchecked")
                List<Object> mutable = (List<Object>) raw;
                for (int i = mutable.size() - 1; i >= 0; i--) {
                    Object pi = mutable.get(i);
                    try {
                        Object n = getFieldValue(pi, "filterName");
                        if (filterName.equals(String.valueOf(n))) {
                            mutable.remove(i);
                        }
                    } catch (Exception ignored) {
                    }
                }
            }
        } catch (Exception ignored) {
        }
        // 删 filters map
        try {
            Method remove = findCompatibleMethod(filters.getClass(), "remove", filterName);
            if (remove != null) {
                remove.invoke(filters, filterName);
            } else {
                ((Map) filters).remove(filterName);
            }
        } catch (Exception e) {
            ((Map) filters).remove(filterName);
        }
        removeCachedClass(context, className);
    }

    public static synchronized void deleteServlet(Object context, String servletName) throws Exception {
        Map<?, ?> stubs = asMap(getFieldValue(context, "servletStubs"));
        Object stub = stubs.get(servletName);
        if (stub == null) {
            throw new IllegalArgumentException("Servlet 不存在: " + servletName);
        }
        String className = null;
        try {
            Object servlet = null;
            try {
                servlet = getFieldValue(stub, "servlet");
            } catch (Exception ignored) {
            }
            if (servlet != null) {
                className = servlet.getClass().getName();
                try {
                    invokeName(servlet, "destroy");
                } catch (Exception ignored) {
                }
            }
        } catch (Exception ignored) {
        }
        if (className == null) {
            try {
                Object cn = getFieldValue(stub, "className");
                if (cn != null) {
                    className = String.valueOf(cn);
                }
            } catch (Exception ignored) {
            }
        }
        // 清理 URL mapping
        try {
            Object servletMapping = null;
            try {
                servletMapping = invokeName(context, "getServletMapping");
            } catch (Exception ignored) {
            }
            if (servletMapping == null) {
                servletMapping = getFieldValue(context, "servletMapping");
            }
            removeServletPatterns(servletMapping, servletName);
        } catch (Exception ignored) {
        }
        try {
            ((Map) stubs).remove(servletName);
        } catch (Exception e) {
            throw e;
        }
        removeCachedClass(context, className);
    }

    public static void removeServletPatterns(Object mappingNode, String servletName) {
        if (mappingNode == null) {
            return;
        }
        for (String field : new String[]{"matchMap", "extensionMap", "pathMap", "defaultMap"}) {
            try {
                Object mapObj = getFieldValue(mappingNode, field);
                if (!(mapObj instanceof Map)) {
                    continue;
                }
                Map map = (Map) mapObj;
                List<Object> toRemove = new ArrayList<Object>();
                for (Object key : map.keySet()) {
                    String sn = resolveServletNameFromMappingValue(map.get(key));
                    if (servletName.equals(sn)) {
                        toRemove.add(key);
                    }
                }
                for (Object k : toRemove) {
                    map.remove(k);
                }
            } catch (Exception ignored) {
            }
        }
        if (mappingNode instanceof Map) {
            Map map = (Map) mappingNode;
            List<Object> toRemove = new ArrayList<Object>();
            for (Object key : map.keySet()) {
                String sn = resolveServletNameFromMappingValue(map.get(key));
                if (servletName.equals(sn)) {
                    toRemove.add(key);
                }
            }
            for (Object k : toRemove) {
                map.remove(k);
            }
        }
    }

    public static synchronized void deleteListener(Object context, String className) throws Exception {
        Object events = getEventsManager(context);
        String[] fields = new String[]{
                "requestListeners", "ctxListeners", "sessionListeners", "sessionIdListeners",
                "contextAttributeListeners", "requestAttributeListeners", "sessionAttributeListeners",
                "sessionActivationListeners", "sessionBindingListeners"
        };
        boolean removed = false;
        for (int i = 0; i < fields.length; i++) {
            Field f = findField(events.getClass(), fields[i]);
            if (f == null) {
                continue;
            }
            Object val = f.get(events);
            if (val instanceof List) {
                List list = (List) val;
                for (int j = list.size() - 1; j >= 0; j--) {
                    Object o = list.get(j);
                    if (o != null && className.equals(o.getClass().getName())) {
                        list.remove(j);
                        removed = true;
                    }
                }
            } else if (val != null && val.getClass().isArray()) {
                int n = Array.getLength(val);
                List<Object> kept = new ArrayList<Object>();
                for (int j = 0; j < n; j++) {
                    Object o = Array.get(val, j);
                    if (o != null && className.equals(o.getClass().getName())) {
                        removed = true;
                    } else if (o != null) {
                        kept.add(o);
                    }
                }
                f.set(events, kept.toArray((Object[]) Array.newInstance(val.getClass().getComponentType(), 0)));
            }
        }
        // 同步 hasRequestListeners 标记
        try {
            List<?> req = asList(getFieldValue(events, "requestListeners"));
            Field flag = findField(events.getClass(), "hasRequestListeners");
            if (flag != null && flag.getType() == boolean.class) {
                flag.setBoolean(events, !req.isEmpty());
            }
        } catch (Exception ignored) {
        }
        removeCachedClass(context, className);
        if (!removed) {
            throw new IllegalArgumentException("未找到 Listener: " + className);
        }
    }

    public static void removeCachedClass(Object context, String className) {
        if (className == null || className.length() == 0 || "-".equals(className)) {
            return;
        }
        try {
            ClassLoader cl = null;
            try {
                cl = (ClassLoader) invokeName(context, "getServletClassLoader");
            } catch (Exception ignored) {
            }
            if (cl == null) {
                cl = (ClassLoader) getFieldValue(context, "classLoader");
            }
            Object cached = getFieldValue(cl, "cachedClasses");
            if (cached instanceof Map) {
                ((Map) cached).remove(className);
            }
        } catch (Exception ignored) {
        }
    }

    public static byte[] dumpClassBytes(Class<?> clazz) throws Exception {
        String path = clazz.getName().replace('.', '/') + ".class";
        InputStream in = null;
        try {
            ClassLoader cl = clazz.getClassLoader();
            in = cl == null ? ClassLoader.getSystemResourceAsStream(path) : cl.getResourceAsStream(path);
            if (in != null) {
                ByteArrayOutputStream bos = new ByteArrayOutputStream();
                byte[] buf = new byte[4096];
                int n;
                while ((n = in.read(buf)) > 0) {
                    bos.write(buf, 0, n);
                }
                return bos.toByteArray();
            }
        } finally {
            if (in != null) {
                try {
                    in.close();
                } catch (Exception ignored) {
                }
            }
        }
        Class<?> repo = tryClass("com.sun.org.apache.bcel.internal.Repository", "org.apache.bcel.Repository");
        if (repo != null) {
            Method lookup = findCompatibleMethod(repo, "lookupClass", clazz);
            if (lookup == null) {
                lookup = findCompatibleMethod(repo, "lookupClass", clazz.getName());
            }
            if (lookup != null) {
                Object javaClass = lookup.getParameterTypes()[0] == Class.class
                        ? lookup.invoke(null, clazz) : lookup.invoke(null, clazz.getName());
                if (javaClass != null) {
                    Method getBytes = findCompatibleMethod(javaClass.getClass(), "getBytes");
                    if (getBytes != null) {
                        return (byte[]) getBytes.invoke(javaClass);
                    }
                }
            }
        }
        throw new IllegalStateException("无法 dump，建议 Arthas: jad --source-only " + clazz.getName());
    }

    public static void writeTableStart(Object out, String title, String tip, String[] headers) throws Exception {
        writeOut(out, "<h4 style=\"margin:18px 0 6px\">" + html(title) + "</h4>");
        if (tip != null) {
            writeOut(out, "<div style=\"color:#666;font-size:12px;margin-bottom:6px\">" + tip + "</div>");
        }
        writeOut(out, "<table border=\"1\" cellspacing=\"0\" width=\"98%\" style=\"table-layout:fixed;word-break:break-all;background:#f7f7f7;font-size:13px\"><thead><tr>");
        for (int i = 0; i < headers.length; i++) {
            writeOut(out, "<th>" + html(headers[i]) + "</th>");
        }
        writeOut(out, "</tr></thead><tbody>");
    }

    public static void writeTableEnd(Object out) throws Exception {
        writeOut(out, "</tbody></table>");
    }

    public static String dumpLink(String className) throws Exception {
        return "?action=dump&className=" + URLEncoder.encode(className, "UTF-8");
    }

    public static String killLink(String q) {
        return "?action=kill&" + q;
    }
%>
<%-- dump 必须在任何 HTML 输出之前 --%>
<%
    if ("dump".equals(request.getParameter("action")) && request.getParameter("className") != null) {
        String __dumpClass = request.getParameter("className");
        try {
            Class<?> __clazz = loadClassFlexible(__dumpClass);
            byte[] __bytes = dumpClassBytes(__clazz);
            response.reset();
            response.setContentType("application/octet-stream");
            String __filename = __clazz.getSimpleName();
            if (__filename == null || __filename.length() == 0) {
                __filename = "MemShell";
            }
            __filename = __filename + ".class";
            response.setHeader("Content-Disposition",
                    "attachment;filename=" + URLEncoder.encode(__filename, "UTF-8"));
            Object __sos = invokeName(response, "getOutputStream");
            Method __write = findCompatibleMethod(__sos.getClass(), "write", __bytes);
            if (__write == null) {
                __write = findCompatibleMethod(__sos.getClass(), "write", __bytes,
                        Integer.valueOf(0), Integer.valueOf(__bytes.length));
                __write.invoke(__sos, new Object[]{__bytes, Integer.valueOf(0), Integer.valueOf(__bytes.length)});
            } else if (__write.getParameterTypes().length == 1) {
                __write.invoke(__sos, new Object[]{__bytes});
            } else {
                __write.invoke(__sos, new Object[]{__bytes, Integer.valueOf(0), Integer.valueOf(__bytes.length)});
            }
        } catch (Exception __e) {
            response.reset();
            response.setContentType("text/html;charset=UTF-8");
            out.write("<h3>dump 失败</h3><pre>" + html(__e.toString()) + "</pre>");
        }
        return;
    }
%>
<html>
<head>
    <title>weblogic-memshell-scanner <%=VERSION%></title>
    <style>
        body { font-family: Menlo, Consolas, Monaco, monospace; margin: 16px; color: #222; }
        .meta { background: #eef8f0; padding: 10px 12px; border: 1px solid #b7e0c0; margin-bottom: 12px; }
        .ok { color: #1e8449; } .err { color: #c0392b; }
        a { color: #1a5276; } th { background: #dcefe0; } td, th { padding: 4px 6px; }
    </style>
</head>
<body>
<%
    // 快速探测：非 WebLogic 给出明确提示
    if (tryClass("weblogic.servlet.internal.WebAppServletContext") == null) {
        out.write("<h2>weblogic-memshell-scanner " + VERSION + "</h2>");
        out.write("<div class=\"err\">当前 JVM 未检测到 WebLogic 类（weblogic.servlet.internal.WebAppServletContext）。请将本 JSP 部署到 WebLogic 域中访问。</div>");
        out.write("<p>Tomcat 请使用 <code>tomcat-memshell-scanner.jsp</code>。</p>");
        return;
    }

    Object context;
    String info;
    try {
        context = getWebAppServletContext(request);
        info = detectWebLogicInfo(context);
    } catch (Exception e) {
        out.write("<h2>无法获取 WebAppServletContext</h2><pre class=\"err\">" + html(e.toString()) + "</pre>");
        return;
    }

    String action = request.getParameter("action");
    String self = request.getRequestURI();

    if ("kill".equals(action)) {
        String msg;
        String type = "ok";
        try {
            if (request.getParameter("filterName") != null) {
                deleteFilter(context, request.getParameter("filterName"));
                msg = "Filter 已删除: " + request.getParameter("filterName");
            } else if (request.getParameter("servletName") != null) {
                deleteServlet(context, request.getParameter("servletName"));
                msg = "Servlet 已删除: " + request.getParameter("servletName");
            } else if (request.getParameter("listenerName") != null) {
                deleteListener(context, request.getParameter("listenerName"));
                msg = "Listener 已删除: " + request.getParameter("listenerName");
            } else {
                type = "err";
                msg = "未知 kill 参数";
            }
        } catch (Exception e) {
            type = "err";
            msg = "操作失败: " + e.getMessage();
        }
        out.write("<div class=\"" + type + "\">" + html(msg) + "</div>");
        out.write("<p><a href=\"" + html(self) + "\">返回扫描页</a></p>");
        return;
    }

%>
<h2>WebLogic MemShell Scanner <%=VERSION%></h2>
<div class="meta">
    目标：扫描并查杀 WebLogic 内存马 &nbsp;|&nbsp; <%=html(info)%> &nbsp;|&nbsp;
    JDK：<%=html(System.getProperty("java.version"))%><br/>
    覆盖：Filter / Servlet / Listener / ClassLoader.cachedClasses；适配 10.3.6 / 12c / 14c 常见字段差异。
</div>
<%
    // Filter
    try {
        writeTableStart(out, "Filter", "来源：FilterManager.filters + filterPatternList；查杀会同步清理 mapping 与 cachedClasses",
                new String[]{"ID", "Filter name", "Pattern", "Class", "ClassLoader", "Class path", "Judge", "dump", "kill"});
        List<FilterInfo> filters = scanFilters(context);
        int id = 0;
        for (FilterInfo fi : filters) {
            id++;
            out.write("<tr>");
            out.write("<td style=\"text-align:center\">" + id + "</td>");
            out.write("<td>" + html(fi.filterName) + "</td>");
            out.write("<td>" + html(fi.patterns) + "</td>");
            out.write("<td>" + html(fi.className) + "</td>");
            out.write("<td>" + html(fi.clazz == null ? "-" : classLoaderName(fi.clazz)) + "</td>");
            out.write("<td>" + html(fi.clazz == null ? "-" : classFilePath(fi.clazz)) + "</td>");
            out.write("<td>" + (fi.clazz == null ? "-" : judgeClassLocation(fi.clazz)) + "</td>");
            if (fi.clazz != null) {
                out.write("<td style=\"text-align:center\"><a href=\"" + dumpLink(fi.clazz.getName()) + "\">dump</a></td>");
            } else {
                out.write("<td style=\"text-align:center;color:#999\">-</td>");
            }
            out.write("<td style=\"text-align:center\"><a href=\"" + killLink("filterName=" + URLEncoder.encode(fi.filterName, "UTF-8")) + "\">kill</a></td>");
            out.write("</tr>");
        }
        if (id == 0) {
            out.write("<tr><td colspan=\"9\" style=\"text-align:center;color:#666\">未发现 Filter</td></tr>");
        }
        writeTableEnd(out);
    } catch (Exception e) {
        out.write("<div class=\"err\">Filter 扫描失败: " + html(e.toString()) + "</div>");
    }

    // Servlet
    try {
        writeTableStart(out, "Servlet", "来源：servletStubs + servletMapping；内置/系统 Servlet 请谨慎删除",
                new String[]{"ID", "Servlet name", "Pattern", "Class", "ClassLoader", "Class path", "Judge", "dump", "kill"});
        List<ServletInfo> servlets = scanServlets(context);
        int id = 0;
        for (ServletInfo si : servlets) {
            id++;
            boolean builtin = si.className != null && (
                    si.className.startsWith("weblogic.")
                            || si.className.startsWith("com.bea.")
                            || "jsp".equalsIgnoreCase(si.servletName)
                            || si.servletName != null && si.servletName.contains("JspServlet"));
            out.write("<tr>");
            out.write("<td style=\"text-align:center\">" + id + "</td>");
            out.write("<td>" + html(si.servletName) + "</td>");
            out.write("<td>" + html(si.patterns) + "</td>");
            out.write("<td>" + html(si.className) + "</td>");
            out.write("<td>" + html(si.clazz == null ? "-" : classLoaderName(si.clazz)) + "</td>");
            out.write("<td>" + html(si.clazz == null ? "-" : classFilePath(si.clazz)) + "</td>");
            out.write("<td>" + (si.clazz == null ? "-" : judgeClassLocation(si.clazz)) + "</td>");
            if (si.clazz != null) {
                out.write("<td style=\"text-align:center\"><a href=\"" + dumpLink(si.clazz.getName()) + "\">dump</a></td>");
            } else {
                out.write("<td style=\"text-align:center;color:#999\">-</td>");
            }
            if (builtin) {
                out.write("<td style=\"text-align:center;color:#999\">protected</td>");
            } else {
                out.write("<td style=\"text-align:center\"><a href=\"" + killLink("servletName=" + URLEncoder.encode(si.servletName, "UTF-8")) + "\">kill</a></td>");
            }
            out.write("</tr>");
        }
        if (id == 0) {
            out.write("<tr><td colspan=\"9\" style=\"text-align:center;color:#666\">未发现 Servlet</td></tr>");
        }
        writeTableEnd(out);
    } catch (Exception e) {
        out.write("<div class=\"err\">Servlet 扫描失败: " + html(e.toString()) + "</div>");
    }

    // Listener
    try {
        writeTableStart(out, "Listener", "来源：EventsManager 下各类 listener 列表（request/ctx/session/...）",
                new String[]{"ID", "Kind", "Class", "ClassLoader", "Class path", "Judge", "dump", "kill"});
        List<ListenerInfo> listeners = scanListeners(context);
        int id = 0;
        for (ListenerInfo li : listeners) {
            id++;
            boolean builtin = li.clazz.getName().startsWith("weblogic.")
                    || li.clazz.getName().startsWith("com.bea.");
            out.write("<tr>");
            out.write("<td style=\"text-align:center\">" + id + "</td>");
            out.write("<td>" + html(li.kind) + "</td>");
            out.write("<td>" + html(li.clazz.getName()) + "</td>");
            out.write("<td>" + html(classLoaderName(li.clazz)) + "</td>");
            out.write("<td>" + html(classFilePath(li.clazz)) + "</td>");
            out.write("<td>" + judgeClassLocation(li.clazz) + "</td>");
            out.write("<td style=\"text-align:center\"><a href=\"" + dumpLink(li.clazz.getName()) + "\">dump</a></td>");
            if (builtin) {
                out.write("<td style=\"text-align:center;color:#999\">protected</td>");
            } else {
                out.write("<td style=\"text-align:center\"><a href=\"" + killLink("listenerName=" + URLEncoder.encode(li.clazz.getName(), "UTF-8")) + "\">kill</a></td>");
            }
            out.write("</tr>");
        }
        if (id == 0) {
            out.write("<tr><td colspan=\"8\" style=\"text-align:center;color:#666\">未发现 Listener</td></tr>");
        }
        writeTableEnd(out);
    } catch (Exception e) {
        out.write("<div class=\"err\">Listener 扫描失败: " + html(e.toString()) + "</div>");
    }

    // cachedClasses（辅助）
    try {
        writeTableStart(out, "ClassLoader.cachedClasses（无磁盘 class）",
                "WebLogic ChangeAwareClassLoader 缓存中、磁盘无对应资源的类；常见于 defineClass 注入。仅展示，不提供直接 kill（请通过 Filter/Servlet/Listener 卸载）",
                new String[]{"ID", "Class", "ClassLoader", "Judge", "dump"});
        List<Class<?>> cached = scanCachedClasses(context);
        int id = 0;
        for (Class<?> clazz : cached) {
            id++;
            out.write("<tr>");
            out.write("<td style=\"text-align:center\">" + id + "</td>");
            out.write("<td>" + html(clazz.getName()) + "</td>");
            out.write("<td>" + html(classLoaderName(clazz)) + "</td>");
            out.write("<td>" + judgeClassLocation(clazz) + "</td>");
            out.write("<td style=\"text-align:center\"><a href=\"" + dumpLink(clazz.getName()) + "\">dump</a></td>");
            out.write("</tr>");
        }
        if (id == 0) {
            out.write("<tr><td colspan=\"5\" style=\"text-align:center;color:#666\">未发现无磁盘 cachedClasses 条目</td></tr>");
        }
        writeTableEnd(out);
    } catch (Exception e) {
        out.write("<div class=\"err\">cachedClasses 扫描失败: " + html(e.toString()) + "</div>");
    }
%>
<p style="margin-top:20px;color:#888;font-size:12px">
    weblogic-memshell-scanner <%=VERSION%> — 仅用于授权应急响应。Agent/redefineClasses 型不在覆盖范围。
</p>
</body>
</html>
