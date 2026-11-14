<%@ page import="java.io.*" %>
<%@ page import="java.lang.reflect.Constructor" %>
<%@ page import="java.lang.reflect.Field" %>
<%@ page import="java.lang.reflect.Method" %>
<%@ page import="java.net.URL" %>
<%@ page import="java.net.URLEncoder" %>
<%@ page import="java.text.SimpleDateFormat" %>
<%@ page import="java.util.*" %>
<%@ page import="java.util.concurrent.CopyOnWriteArrayList" %>
<%@ page import="java.util.concurrent.TimeUnit" %>
<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%!
    public static final String VERSION = "0.2.0";

    public static Field findField(Class<?> clazz, String name) {
        Class<?> c = clazz;
        while (c != null && c != Object.class) {
            try {
                Field f = c.getDeclaredField(name);
                f.setAccessible(true);
                return f;
            } catch (NoSuchFieldException ignored) {
                c = c.getSuperclass();
            }
        }
        return null;
    }

    public static Object getFieldValue(Object obj, String name) throws Exception {
        if (obj == null) {
            return null;
        }
        Field f = findField(obj.getClass(), name);
        if (f == null) {
            throw new NoSuchFieldException(obj.getClass().getName() + "." + name);
        }
        return f.get(obj);
    }

    public static void setFieldValue(Object obj, String name, Object value) throws Exception {
        Field f = findField(obj.getClass(), name);
        if (f == null) {
            throw new NoSuchFieldException(obj.getClass().getName() + "." + name);
        }
        f.set(obj, value);
    }

    public static Method findMethod(Class<?> clazz, String name, Class<?>... params) {
        Class<?> c = clazz;
        while (c != null && c != Object.class) {
            try {
                Method m = c.getDeclaredMethod(name, params);
                m.setAccessible(true);
                return m;
            } catch (NoSuchMethodException ignored) {
                c = c.getSuperclass();
            }
        }
        return null;
    }

    public static Object invoke(Object obj, String method, Class<?>[] params, Object... args) throws Exception {
        Method m = findMethod(obj.getClass(), method, params);
        if (m == null) {
            throw new NoSuchMethodException(obj.getClass().getName() + "." + method);
        }
        return m.invoke(obj, args);
    }

    public static Class<?> tryClass(String... names) {
        for (String n : names) {
            try {
                return Class.forName(n);
            } catch (Throwable ignored) {
            }
        }
        return null;
    }

    public static boolean isInstance(Object obj, String... classNames) {
        if (obj == null) {
            return false;
        }
        for (String n : classNames) {
            Class<?> c = tryClass(n);
            if (c != null && c.isInstance(obj)) {
                return true;
            }
        }
        return false;
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

    /**
     * 多路径获取 StandardContext，兼容 session 未创建、Spring Boot 内嵌 Tomcat、Facade 嵌套。
     */
    public static Object getStandardContext(HttpServletRequest request) throws Exception {
        Exception last = null;

        // 1) request.request.context (Catalina Request)
        try {
            Object coyoteReq = getFieldValue(request, "request");
            if (coyoteReq != null) {
                Object ctx = invoke(coyoteReq, "getContext", new Class[0]);
                if (ctx != null && ctx.getClass().getName().contains("StandardContext")) {
                    return ctx;
                }
                Object ctx2 = getFieldValue(coyoteReq, "context");
                if (ctx2 != null && ctx2.getClass().getName().contains("StandardContext")) {
                    return ctx2;
                }
            }
        } catch (Exception e) {
            last = e;
        }

        // 2) ServletContext facade 链
        try {
            Object servletContext = request.getServletContext();
            for (int i = 0; i < 6 && servletContext != null; i++) {
                if (servletContext.getClass().getName().contains("StandardContext")) {
                    return servletContext;
                }
                Object nested = null;
                try {
                    nested = getFieldValue(servletContext, "context");
                } catch (Exception ignored) {
                }
                if (nested == null) {
                    break;
                }
                if (nested.getClass().getName().contains("StandardContext")) {
                    return nested;
                }
                servletContext = nested;
            }
        } catch (Exception e) {
            last = e;
        }

        // 3) session.getServletContext() 回退（可能新建 session）
        try {
            Object context = request.getSession().getServletContext();
            Object appContext = getFieldValue(context, "context");
            Object standardContext = getFieldValue(appContext, "context");
            if (standardContext != null) {
                return standardContext;
            }
        } catch (Exception e) {
            last = e;
        }

        throw last != null ? last : new IllegalStateException("无法获取 StandardContext");
    }

    public static String detectTomcatInfo(Object standardContext) {
        try {
            Package p = standardContext.getClass().getPackage();
            String impl = p != null ? p.getImplementationVersion() : null;
            if (impl != null && impl.length() > 0) {
                return "Tomcat " + impl;
            }
        } catch (Exception ignored) {
        }
        String serverInfo = "";
        try {
            Method m = findMethod(standardContext.getClass(), "getServerInfo");
            if (m != null) {
                serverInfo = String.valueOf(m.invoke(standardContext));
            }
        } catch (Exception ignored) {
        }
        boolean jakarta = tryClass("jakarta.servlet.Servlet") != null
                && tryClass("javax.servlet.Servlet") == null;
        return (serverInfo.length() > 0 ? serverInfo : "Tomcat")
                + (jakarta ? " (Jakarta EE / Tomcat 10+)" : " (Java EE / javax)");
    }

    @SuppressWarnings("unchecked")
    public static Map<String, Object> getFilterConfigs(Object standardContext) throws Exception {
        Object v = getFieldValue(standardContext, "filterConfigs");
        return v == null ? new HashMap<String, Object>() : (Map<String, Object>) v;
    }

    public static Object[] getFilterMaps(Object standardContext) throws Exception {
        Object filterMaps = getFieldValue(standardContext, "filterMaps");
        if (filterMaps == null) {
            return new Object[0];
        }
        try {
            Field array = findField(filterMaps.getClass(), "array");
            if (array != null) {
                return (Object[]) array.get(filterMaps);
            }
        } catch (Exception ignored) {
        }
        if (filterMaps instanceof Object[]) {
            return (Object[]) filterMaps;
        }
        return new Object[0];
    }

    public static String getFilterName(Object filterMap) throws Exception {
        Method m = findMethod(filterMap.getClass(), "getFilterName");
        return (String) m.invoke(filterMap);
    }

    public static String[] getURLPatterns(Object filterMap) throws Exception {
        Method m = findMethod(filterMap.getClass(), "getURLPatterns");
        Object r = m.invoke(filterMap);
        return r == null ? new String[0] : (String[]) r;
    }

    @SuppressWarnings("unchecked")
    public static Map<String, Object> getChildren(Object standardContext) throws Exception {
        Object v = getFieldValue(standardContext, "children");
        return v == null ? new HashMap<String, Object>() : (Map<String, Object>) v;
    }

    @SuppressWarnings("unchecked")
    public static Map<String, String> getServletMaps(Object standardContext) throws Exception {
        Object v = getFieldValue(standardContext, "servletMappings");
        return v == null ? new HashMap<String, String>() : (Map<String, String>) v;
    }

    /**
     * 收集 Event + Lifecycle Listener，兼容 applicationEventListenersList /
     * applicationEventListenersObjects / applicationLifecycleListenersObjects。
     */
    public static List<Object> getAllListeners(Object standardContext) throws Exception {
        List<Object> result = new ArrayList<Object>();
        Set<Integer> seen = new HashSet<Integer>();

        String[] listFields = new String[]{
                "applicationEventListenersList",
                "applicationEventListenersObjects",
                "applicationLifecycleListenersObjects",
                "applicationLifecycleListenersList"
        };
        for (String fieldName : listFields) {
            Field f = findField(standardContext.getClass(), fieldName);
            if (f == null) {
                continue;
            }
            Object val = f.get(standardContext);
            if (val instanceof List) {
                for (Object o : (List<?>) val) {
                    addUnique(result, seen, o);
                }
            } else if (val instanceof Object[]) {
                for (Object o : (Object[]) val) {
                    addUnique(result, seen, o);
                }
            }
        }

        // getApplicationEventListeners / getApplicationLifecycleListeners
        for (String method : new String[]{"getApplicationEventListeners", "getApplicationLifecycleListeners"}) {
            Method m = findMethod(standardContext.getClass(), method);
            if (m == null) {
                continue;
            }
            try {
                Object[] arr = (Object[]) m.invoke(standardContext);
                if (arr != null) {
                    for (Object o : arr) {
                        addUnique(result, seen, o);
                    }
                }
            } catch (Exception ignored) {
            }
        }
        return result;
    }

    private static void addUnique(List<Object> list, Set<Integer> seen, Object o) {
        if (o == null) {
            return;
        }
        int id = System.identityHashCode(o);
        if (seen.add(id)) {
            list.add(o);
        }
    }

    public static String listenerKind(Object listener) {
        if (listener == null) {
            return "unknown";
        }
        Class<?> c = listener.getClass();
        List<String> kinds = new ArrayList<String>();
        String[][] checks = new String[][]{
                {"ServletRequestListener", "javax.servlet.ServletRequestListener", "jakarta.servlet.ServletRequestListener"},
                {"ServletContextListener", "javax.servlet.ServletContextListener", "jakarta.servlet.ServletContextListener"},
                {"HttpSessionListener", "javax.servlet.http.HttpSessionListener", "jakarta.servlet.http.HttpSessionListener"},
                {"HttpSessionIdListener", "javax.servlet.http.HttpSessionIdListener", "jakarta.servlet.http.HttpSessionIdListener"},
                {"ServletRequestAttributeListener", "javax.servlet.ServletRequestAttributeListener", "jakarta.servlet.ServletRequestAttributeListener"},
                {"ServletContextAttributeListener", "javax.servlet.ServletContextAttributeListener", "jakarta.servlet.ServletContextAttributeListener"},
                {"HttpSessionAttributeListener", "javax.servlet.http.HttpSessionAttributeListener", "jakarta.servlet.http.HttpSessionAttributeListener"}
        };
        for (String[] row : checks) {
            if (isInstance(listener, row[1], row[2])) {
                kinds.add(row[0]);
            }
        }
        if (kinds.isEmpty()) {
            return c.getInterfaces().length > 0 ? c.getInterfaces()[0].getSimpleName() : "Object";
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < kinds.size(); i++) {
            if (i > 0) {
                sb.append(",");
            }
            sb.append(kinds.get(i));
        }
        return sb.toString();
    }

    public static List<ValveInfo> getValveInfos(Object standardContext) throws Exception {
        List<ValveInfo> list = new ArrayList<ValveInfo>();
        collectPipelineValves(standardContext, "Context", list);

        Object parent = null;
        try {
            parent = invoke(standardContext, "getParent", new Class[0]);
        } catch (Exception ignored) {
        }
        if (parent != null) {
            collectPipelineValves(parent, "Host", list);
            Object engine = null;
            try {
                engine = invoke(parent, "getParent", new Class[0]);
            } catch (Exception ignored) {
            }
            if (engine != null) {
                collectPipelineValves(engine, "Engine", list);
            }
        }
        return list;
    }

    private static void collectPipelineValves(Object container, String level, List<ValveInfo> out) {
        try {
            Object pipeline = invoke(container, "getPipeline", new Class[0]);
            if (pipeline == null) {
                return;
            }
            Object[] valves = (Object[]) invoke(pipeline, "getValves", new Class[0]);
            if (valves == null) {
                return;
            }
            for (int i = 0; i < valves.length; i++) {
                ValveInfo info = new ValveInfo();
                info.level = level;
                info.index = i;
                info.valve = valves[i];
                info.pipeline = pipeline;
                info.containerName = String.valueOf(invoke(container, "getName", new Class[0]));
                out.add(info);
            }
        } catch (Exception ignored) {
        }
    }

    public static class ValveInfo {
        public String level;
        public int index;
        public Object valve;
        public Object pipeline;
        public String containerName;
    }

    public static class WsEndpointInfo {
        public String path;
        public Class<?> endpointClass;
        public String matchType; // exact / template
        public Object mapKey;
        public Object mapOwner;
    }

    @SuppressWarnings("unchecked")
    public static List<WsEndpointInfo> getWebSocketEndpoints(HttpServletRequest request) throws Exception {
        List<WsEndpointInfo> result = new ArrayList<WsEndpointInfo>();
        Object container = getWsContainer(request);
        if (container == null) {
            return result;
        }

        // exact match
        try {
            Map<String, Object> exact = (Map<String, Object>) getFieldValue(container, "configExactMatchMap");
            if (exact != null) {
                for (Map.Entry<String, Object> e : exact.entrySet()) {
                    Class<?> ep = extractEndpointClass(e.getValue());
                    if (ep == null) {
                        continue;
                    }
                    WsEndpointInfo info = new WsEndpointInfo();
                    info.path = e.getKey();
                    info.endpointClass = ep;
                    info.matchType = "exact";
                    info.mapKey = e.getKey();
                    info.mapOwner = exact;
                    result.add(info);
                }
            }
        } catch (Exception ignored) {
        }

        // template match
        try {
            Map<?, ?> templateRoot = (Map<?, ?>) getFieldValue(container, "configTemplateMatchMap");
            if (templateRoot != null) {
                for (Object levelMapObj : templateRoot.values()) {
                    if (!(levelMapObj instanceof Map)) {
                        continue;
                    }
                    Map<?, ?> levelMap = (Map<?, ?>) levelMapObj;
                    for (Map.Entry<?, ?> e : levelMap.entrySet()) {
                        Class<?> ep = extractEndpointClass(e.getValue());
                        if (ep == null) {
                            continue;
                        }
                        String path = String.valueOf(e.getKey());
                        try {
                            Object cfg = getConfigFromMatch(e.getValue());
                            if (cfg != null) {
                                Method getPath = findMethod(cfg.getClass(), "getPath");
                                if (getPath != null) {
                                    path = String.valueOf(getPath.invoke(cfg));
                                }
                            }
                        } catch (Exception ignored) {
                        }
                        WsEndpointInfo info = new WsEndpointInfo();
                        info.path = path;
                        info.endpointClass = ep;
                        info.matchType = "template";
                        info.mapKey = e.getKey();
                        info.mapOwner = levelMap;
                        result.add(info);
                    }
                }
            }
        } catch (Exception ignored) {
        }
        return result;
    }

    public static Object getWsContainer(HttpServletRequest request) {
        try {
            Object sc = request.getServletContext();
            String[] keys = new String[]{
                    "javax.websocket.server.ServerContainer",
                    "jakarta.websocket.server.ServerContainer"
            };
            for (String key : keys) {
                Object c = invoke(sc, "getAttribute", new Class[]{String.class}, key);
                if (c != null) {
                    return c;
                }
            }
            // fallback Class.forName().getName()
            Class<?> c1 = tryClass("javax.websocket.server.ServerContainer", "jakarta.websocket.server.ServerContainer");
            if (c1 != null) {
                return invoke(sc, "getAttribute", new Class[]{String.class}, c1.getName());
            }
        } catch (Exception ignored) {
        }
        return null;
    }

    private static Object getConfigFromMatch(Object match) {
        if (match == null) {
            return null;
        }
        try {
            Method getConfig = findMethod(match.getClass(), "getConfig");
            if (getConfig != null) {
                return getConfig.invoke(match);
            }
        } catch (Exception ignored) {
        }
        try {
            return getFieldValue(match, "config");
        } catch (Exception ignored) {
        }
        return null;
    }

    private static Class<?> extractEndpointClass(Object match) {
        try {
            Object cfg = getConfigFromMatch(match);
            if (cfg == null) {
                return null;
            }
            Method getEndpointClass = findMethod(cfg.getClass(), "getEndpointClass");
            if (getEndpointClass != null) {
                return (Class<?>) getEndpointClass.invoke(cfg);
            }
        } catch (Exception ignored) {
        }
        return null;
    }

    public static Map<String, Object> getUpgradeProtocols(HttpServletRequest request) throws Exception {
        Object coyoteReq = getFieldValue(request, "request");
        Object connector = getFieldValue(coyoteReq, "connector");
        Object protocolHandler = getFieldValue(connector, "protocolHandler");
        Object map = getFieldValue(protocolHandler, "httpUpgradeProtocols");
        if (map instanceof Map) {
            @SuppressWarnings("unchecked")
            Map<String, Object> m = (Map<String, Object>) map;
            return m;
        }
        return new HashMap<String, Object>();
    }

    public static Object getEndpoint(HttpServletRequest request) throws Exception {
        Object coyoteReq = getFieldValue(request, "request");
        Object connector = getFieldValue(coyoteReq, "connector");
        Object protocolHandler = getFieldValue(connector, "protocolHandler");
        // AbstractProtocol.endpoint
        Object endpoint = null;
        try {
            endpoint = getFieldValue(protocolHandler, "endpoint");
        } catch (Exception ignored) {
        }
        if (endpoint == null) {
            try {
                endpoint = invoke(protocolHandler, "getEndpoint", new Class[0]);
            } catch (Exception ignored) {
            }
        }
        if (endpoint != null) {
            return endpoint;
        }
        // 回退：从 Poller/Acceptor 线程找 this$0
        return findEndpointFromThreads();
    }

    public static Object findEndpointFromThreads() throws Exception {
        Thread[] threads = getAllThreads();
        for (Thread t : threads) {
            if (t == null || t.getName() == null) {
                continue;
            }
            String name = t.getName();
            if (!(name.contains("Poller") || name.contains("Acceptor") || name.contains("Keeper"))) {
                continue;
            }
            try {
                Object target = getFieldValue(t, "target");
                if (target == null) {
                    continue;
                }
                Field outer = findField(target.getClass(), "this$0");
                if (outer != null) {
                    Object ep = outer.get(target);
                    if (ep != null && ep.getClass().getName().contains("Endpoint")) {
                        return ep;
                    }
                }
            } catch (Exception ignored) {
            }
        }
        return null;
    }

    public static Thread[] getAllThreads() throws Exception {
        ThreadGroup group = Thread.currentThread().getThreadGroup();
        while (group.getParent() != null) {
            group = group.getParent();
        }
        int estimated = group.activeCount() * 2;
        Thread[] threads = new Thread[Math.max(estimated, 64)];
        int n = group.enumerate(threads, true);
        return Arrays.copyOf(threads, n);
    }

    public static List<TimerInfo> getTimerTasks() throws Exception {
        List<TimerInfo> list = new ArrayList<TimerInfo>();
        Thread[] threads = getAllThreads();
        for (Thread thread : threads) {
            if (thread == null) {
                continue;
            }
            if (!"java.util.TimerThread".equals(thread.getClass().getName())) {
                continue;
            }
            try {
                Object queue = getFieldValue(thread, "queue");
                Method sizeMethod = findMethod(queue.getClass(), "size");
                int size = sizeMethod != null ? ((Integer) sizeMethod.invoke(queue)).intValue() : 1;
                Method getMethod = findMethod(queue.getClass(), "get", int.class);
                if (getMethod == null) {
                    continue;
                }
                // TaskQueue 下标从 1 开始
                for (int i = 1; i <= Math.max(size, 1) + 2; i++) {
                    TimerTask task = null;
                    try {
                        task = (TimerTask) getMethod.invoke(queue, Integer.valueOf(i));
                    } catch (Exception ignored) {
                        break;
                    }
                    if (task == null) {
                        continue;
                    }
                    TimerInfo info = new TimerInfo();
                    info.threadName = thread.getName();
                    info.task = task;
                    info.queueIndex = i;
                    list.add(info);
                }
            } catch (Exception ignored) {
            }
        }
        return list;
    }

    public static class TimerInfo {
        public String threadName;
        public TimerTask task;
        public int queueIndex;
    }

    /**
     * 完整删除 Filter：filterDef + filterMap + filterConfigs，避免遗留可复活配置。
     */
    public static synchronized void deleteFilter(Object standardContext, String filterName) throws Exception {
        Map<String, Object> filterConfigs = getFilterConfigs(standardContext);
        Object appFilterConfig = filterConfigs.get(filterName);
        if (appFilterConfig == null) {
            throw new IllegalArgumentException("filter 不存在: " + filterName);
        }

        Object filterDef = getFieldValue(appFilterConfig, "filterDef");
        Class<?> clsFilterDef = tryClass(
                "org.apache.tomcat.util.descriptor.web.FilterDef",
                "org.apache.catalina.deploy.FilterDef");
        Class<?> clsFilterMap = tryClass(
                "org.apache.tomcat.util.descriptor.web.FilterMap",
                "org.apache.catalina.deploy.FilterMap");

        // destroy filter instance if possible
        try {
            Object filter = getFieldValue(appFilterConfig, "filter");
            if (filter != null) {
                Method destroy = findMethod(filter.getClass(), "destroy");
                if (destroy != null) {
                    destroy.invoke(filter);
                }
            }
        } catch (Exception ignored) {
        }

        Method removeFilterDef = findMethod(standardContext.getClass(), "removeFilterDef", clsFilterDef);
        if (removeFilterDef != null) {
            removeFilterDef.invoke(standardContext, filterDef);
        }

        Object[] filterMaps = getFilterMaps(standardContext);
        Method removeFilterMap = findMethod(standardContext.getClass(), "removeFilterMap", clsFilterMap);
        for (Object filterMap : filterMaps) {
            if (filterName.equals(getFilterName(filterMap)) && removeFilterMap != null) {
                removeFilterMap.invoke(standardContext, filterMap);
            }
        }

        // 兜底清理 filterConfigs / filterDefs（原注释中的遗留问题）
        try {
            filterConfigs.remove(filterName);
        } catch (Exception ignored) {
        }
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> filterDefs = (Map<String, Object>) getFieldValue(standardContext, "filterDefs");
            if (filterDefs != null) {
                filterDefs.remove(filterName);
            }
        } catch (Exception ignored) {
        }
    }

    public static synchronized void deleteServlet(Object standardContext, String servletName) throws Exception {
        Map<String, Object> children = getChildren(standardContext);
        Object objChild = children.get(servletName);
        List<String> patterns = new ArrayList<String>();
        Map<String, String> servletMaps = getServletMaps(standardContext);
        for (Map.Entry<String, String> e : servletMaps.entrySet()) {
            if (servletName.equals(e.getValue())) {
                patterns.add(e.getKey());
            }
        }
        Method removeServletMapping = findMethod(standardContext.getClass(), "removeServletMapping", String.class);
        for (String pattern : patterns) {
            if (removeServletMapping != null) {
                removeServletMapping.invoke(standardContext, pattern);
            }
        }
        if (objChild != null) {
            Class<?> containerCls = tryClass("org.apache.catalina.Container");
            Method removeChild = findMethod(standardContext.getClass(), "removeChild", containerCls);
            if (removeChild != null) {
                removeChild.invoke(standardContext, objChild);
            }
        }
    }

    public static synchronized void deleteListener(Object standardContext, String listenerClassName) throws Exception {
        // event listeners list
        Field listField = findField(standardContext.getClass(), "applicationEventListenersList");
        if (listField != null) {
            Object val = listField.get(standardContext);
            if (val instanceof List) {
                @SuppressWarnings("unchecked")
                List<Object> list = (List<Object>) val;
                List<Object> kept = new CopyOnWriteArrayList<Object>();
                for (Object o : list) {
                    if (o != null && !o.getClass().getName().equals(listenerClassName)) {
                        kept.add(o);
                    }
                }
                // Prefer official setter when available
                Method setter = findMethod(standardContext.getClass(), "setApplicationEventListeners", Object[].class);
                if (setter != null) {
                    setter.invoke(standardContext, new Object[]{kept.toArray()});
                } else {
                    listField.set(standardContext, kept);
                }
            }
        }

        // lifecycle / objects arrays
        String[] arrayFields = new String[]{
                "applicationEventListenersObjects",
                "applicationLifecycleListenersObjects"
        };
        for (String fn : arrayFields) {
            Field f = findField(standardContext.getClass(), fn);
            if (f == null) {
                continue;
            }
            Object val = f.get(standardContext);
            if (!(val instanceof Object[])) {
                continue;
            }
            Object[] arr = (Object[]) val;
            List<Object> kept = new ArrayList<Object>();
            for (Object o : arr) {
                if (o != null && !o.getClass().getName().equals(listenerClassName)) {
                    kept.add(o);
                }
            }
            f.set(standardContext, kept.toArray(new Object[0]));
        }

        Field lifeList = findField(standardContext.getClass(), "applicationLifecycleListenersList");
        if (lifeList != null) {
            Object val = lifeList.get(standardContext);
            if (val instanceof List) {
                @SuppressWarnings("unchecked")
                List<Object> list = (List<Object>) val;
                Iterator<Object> it = list.iterator();
                // CopyOnWriteArrayList iterator 不支持 remove，重建
                List<Object> kept = new CopyOnWriteArrayList<Object>();
                for (Object o : list) {
                    if (o != null && !o.getClass().getName().equals(listenerClassName)) {
                        kept.add(o);
                    }
                }
                lifeList.set(standardContext, kept);
            }
        }
    }

    public static synchronized void deleteValve(Object standardContext, String level, int index) throws Exception {
        List<ValveInfo> infos = getValveInfos(standardContext);
        for (ValveInfo info : infos) {
            if (info.level.equals(level) && info.index == index) {
                String cn = info.valve.getClass().getName();
                if (cn.contains("StandardContextValve")
                        || cn.contains("StandardHostValve")
                        || cn.contains("StandardEngineValve")
                        || cn.contains("ErrorReportValve")) {
                    throw new IllegalStateException("拒绝删除 Tomcat 内置 Valve: " + cn);
                }
                Class<?> valveCls = tryClass("org.apache.catalina.Valve");
                if (valveCls == null) {
                    // 兜底：按运行时接口匹配 removeValve(Valve)
                    Method[] methods = info.pipeline.getClass().getMethods();
                    Method remove = null;
                    for (Method m : methods) {
                        if ("removeValve".equals(m.getName()) && m.getParameterTypes().length == 1) {
                            remove = m;
                            break;
                        }
                    }
                    if (remove == null) {
                        throw new NoSuchMethodException("removeValve");
                    }
                    remove.setAccessible(true);
                    remove.invoke(info.pipeline, info.valve);
                } else {
                    invoke(info.pipeline, "removeValve", new Class[]{valveCls}, info.valve);
                }
                return;
            }
        }
        throw new IllegalArgumentException("未找到 Valve: " + level + "#" + index);
    }

    @SuppressWarnings("unchecked")
    public static synchronized void deleteWebSocket(HttpServletRequest request, String path) throws Exception {
        List<WsEndpointInfo> endpoints = getWebSocketEndpoints(request);
        boolean removed = false;
        for (WsEndpointInfo info : endpoints) {
            if (path.equals(info.path) && info.mapOwner instanceof Map) {
                ((Map<Object, Object>) info.mapOwner).remove(info.mapKey);
                removed = true;
            }
        }
        if (!removed) {
            // 直接按 exact path 再试一次
            Object container = getWsContainer(request);
            if (container != null) {
                Map<String, Object> exact = (Map<String, Object>) getFieldValue(container, "configExactMatchMap");
                if (exact != null && exact.remove(path) != null) {
                    removed = true;
                }
            }
        }
        if (!removed) {
            throw new IllegalArgumentException("未找到 WebSocket: " + path);
        }
    }

    public static synchronized void deleteUpgrade(HttpServletRequest request, String key) throws Exception {
        Map<String, Object> map = getUpgradeProtocols(request);
        if (map.remove(key) == null) {
            throw new IllegalArgumentException("未找到 Upgrade: " + key);
        }
    }

    public static synchronized void deleteTimer(String threadName) throws Exception {
        Thread[] threads = getAllThreads();
        for (Thread thread : threads) {
            if (thread == null || !threadName.equals(thread.getName())) {
                continue;
            }
            if (!"java.util.TimerThread".equals(thread.getClass().getName())) {
                continue;
            }
            Object queue = getFieldValue(thread, "queue");
            Method getMethod = findMethod(queue.getClass(), "get", int.class);
            Method sizeMethod = findMethod(queue.getClass(), "size");
            int size = sizeMethod != null ? ((Integer) sizeMethod.invoke(queue)).intValue() : 8;
            boolean cancelled = false;
            for (int i = 1; i <= Math.max(size, 1) + 8; i++) {
                TimerTask task;
                try {
                    task = (TimerTask) getMethod.invoke(queue, Integer.valueOf(i));
                } catch (Exception e) {
                    break;
                }
                if (task != null) {
                    task.cancel();
                    cancelled = true;
                }
            }
            // 打断 Timer 线程，阻止继续调度
            try {
                setFieldValue(thread, "newTasksMayBeScheduled", Boolean.FALSE);
            } catch (Exception ignored) {
            }
            thread.interrupt();
            if (!cancelled) {
                throw new IllegalStateException("Timer 队列为空或无法取消任务: " + threadName);
            }
            return;
        }
        throw new IllegalArgumentException("未找到 Timer 线程: " + threadName);
    }

    public static synchronized void recoverExecutor(HttpServletRequest request) throws Exception {
        Object endpoint = getEndpoint(request);
        if (endpoint == null) {
            throw new IllegalStateException("无法定位 Endpoint");
        }
        Object executor = invoke(endpoint, "getExecutor", new Class[0]);
        if (executor == null) {
            throw new IllegalStateException("Endpoint 无 Executor");
        }
        String cn = executor.getClass().getName();
        if ("org.apache.tomcat.util.threads.ThreadPoolExecutor".equals(cn)
                || "java.util.concurrent.ThreadPoolExecutor".equals(cn)) {
            throw new IllegalStateException("当前 Executor 已是标准实现，无需恢复: " + cn);
        }

        int core = ((Number) invoke(executor, "getCorePoolSize", new Class[0])).intValue();
        int max = ((Number) invoke(executor, "getMaximumPoolSize", new Class[0])).intValue();
        long keepAlive = ((Number) invoke(executor, "getKeepAliveTime",
                new Class[]{TimeUnit.class}, TimeUnit.MILLISECONDS)).longValue();
        Object queue = invoke(executor, "getQueue", new Class[0]);
        Object threadFactory = invoke(executor, "getThreadFactory", new Class[0]);
        Object handler = invoke(executor, "getRejectedExecutionHandler", new Class[0]);

        Class<?> tpe = tryClass("org.apache.tomcat.util.threads.ThreadPoolExecutor");
        if (tpe == null) {
            throw new IllegalStateException("找不到 org.apache.tomcat.util.threads.ThreadPoolExecutor");
        }
        Constructor<?> ctor = tpe.getConstructor(
                int.class, int.class, long.class, TimeUnit.class,
                Class.forName("java.util.concurrent.BlockingQueue"),
                Class.forName("java.util.concurrent.ThreadFactory"),
                Class.forName("java.util.concurrent.RejectedExecutionHandler"));
        Object fresh = ctor.newInstance(Integer.valueOf(core), Integer.valueOf(max),
                Long.valueOf(keepAlive), TimeUnit.MILLISECONDS, queue, threadFactory, handler);
        invoke(endpoint, "setExecutor", new Class[]{Class.forName("java.util.concurrent.Executor")}, fresh);
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
            if (urlStr.contains("/work/") || urlStr.contains("/Work/")
                    || urlStr.contains(File.separator + "work" + File.separator)) {
                return "<span style=\"color:#d35400;font-weight:bold\">来自 work 目录：可疑</span>";
            }
            if (urlStr.contains(".jar!")) {
                String jarPath = urlStr.substring(0, urlStr.indexOf('!')).replaceFirst("^jar:file:", "");
                File jarFile = new File(jarPath);
                String time = jarFile.exists()
                        ? new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new Date(jarFile.lastModified()))
                        : "unknown";
                return "来自依赖 jar，mtime=" + time;
            }
            if (urlStr.contains("/WEB-INF/classes/") || urlStr.contains("/WEB-INF/classes/".replace('/', File.separatorChar))) {
                return "来自 WEB-INF/classes";
            }
            return "已找到 class 资源";
        } catch (Exception e) {
            return "无法判断";
        }
    }

    public static byte[] dumpClassBytes(Class<?> clazz) throws Exception {
        // 1) ClassLoader resource
        String path = clazz.getName().replace('.', '/') + ".class";
        InputStream in = null;
        try {
            ClassLoader cl = clazz.getClassLoader();
            in = cl == null ? ClassLoader.getSystemResourceAsStream(path) : cl.getResourceAsStream(path);
            if (in != null) {
                return readAll(in);
            }
        } finally {
            if (in != null) {
                try {
                    in.close();
                } catch (Exception ignored) {
                }
            }
        }

        // 2) BCEL internal (JDK8) / optional apache bcel
        Class<?> repo = tryClass(
                "com.sun.org.apache.bcel.internal.Repository",
                "org.apache.bcel.Repository");
        if (repo != null) {
            Method lookup = findMethod(repo, "lookupClass", Class.class);
            if (lookup == null) {
                lookup = findMethod(repo, "lookupClass", String.class);
            }
            Object javaClass = lookup.getParameterTypes()[0] == Class.class
                    ? lookup.invoke(null, clazz)
                    : lookup.invoke(null, clazz.getName());
            if (javaClass != null) {
                Method getBytes = findMethod(javaClass.getClass(), "getBytes");
                if (getBytes != null) {
                    return (byte[]) getBytes.invoke(javaClass);
                }
            }
        }
        throw new IllegalStateException("无法从磁盘/BCEL dump 该类，建议使用 Arthas: jad --source-only " + clazz.getName());
    }

    private static byte[] readAll(InputStream in) throws IOException {
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        byte[] buf = new byte[4096];
        int n;
        while ((n = in.read(buf)) > 0) {
            bos.write(buf, 0, n);
        }
        return bos.toByteArray();
    }

    public static String arrayToString(String[] str) {
        if (str == null || str.length == 0) {
            return "[]";
        }
        StringBuilder sb = new StringBuilder("[");
        for (int i = 0; i < str.length; i++) {
            if (i > 0) {
                sb.append(",");
            }
            sb.append(str[i]);
        }
        sb.append("]");
        return sb.toString();
    }

    public static void writeTableStart(JspWriter out, String title, String tip, String[] headers) throws Exception {
        out.write("<h4 style=\"margin:18px 0 6px\">" + html(title) + "</h4>");
        if (tip != null && tip.length() > 0) {
            out.write("<div style=\"color:#666;font-size:12px;margin-bottom:6px\">" + tip + "</div>");
        }
        out.write("<table border=\"1\" cellspacing=\"0\" width=\"98%\" style=\"table-layout:fixed;word-break:break-all;background:#f7f7f7;font-size:13px\">");
        out.write("<thead><tr>");
        for (String h : headers) {
            out.write("<th>" + html(h) + "</th>");
        }
        out.write("</tr></thead><tbody>");
    }

    public static void writeTableEnd(JspWriter out) throws Exception {
        out.write("</tbody></table>");
    }

    public static String dumpLink(String className) {
        try {
            return "?action=dump&className=" + URLEncoder.encode(className, "UTF-8");
        } catch (Exception e) {
            return "?action=dump&className=" + className;
        }
    }

    public static String killLink(String query) {
        return "?action=kill&" + query;
    }
%>
<html>
<head>
    <title>tomcat-memshell-scanner <%=VERSION%></title>
    <style>
        body { font-family: Menlo, Consolas, Monaco, monospace; margin: 16px; color: #222; }
        .meta { background: #eef5ff; padding: 10px 12px; border: 1px solid #c9daf8; margin-bottom: 12px; }
        .ok { color: #1e8449; }
        .err { color: #c0392b; }
        a { color: #1a5276; }
        th { background: #dde6f0; }
        td, th { padding: 4px 6px; }
    </style>
</head>
<body>
<%
    Object standardContext = null;
    String tomcatInfo = "unknown";
    String contextName = "-";
    try {
        standardContext = getStandardContext(request);
        tomcatInfo = detectTomcatInfo(standardContext);
        try {
            contextName = String.valueOf(invoke(standardContext, "getName", new Class[0]));
        } catch (Exception ignored) {
        }
    } catch (Exception e) {
        out.write("<h2>无法获取 StandardContext</h2><pre class=\"err\">" + html(e.toString()) + "</pre>");
        return;
    }

    String action = request.getParameter("action");
    String self = request.getRequestURI();

    if ("kill".equals(action)) {
        String msg;
        String type = "ok";
        try {
            if (request.getParameter("filterName") != null) {
                deleteFilter(standardContext, request.getParameter("filterName"));
                msg = "Filter 已删除: " + request.getParameter("filterName");
            } else if (request.getParameter("servletName") != null) {
                deleteServlet(standardContext, request.getParameter("servletName"));
                msg = "Servlet 已删除: " + request.getParameter("servletName");
            } else if (request.getParameter("listenerName") != null) {
                deleteListener(standardContext, request.getParameter("listenerName"));
                msg = "Listener 已删除: " + request.getParameter("listenerName");
            } else if (request.getParameter("valveLevel") != null && request.getParameter("valveIndex") != null) {
                deleteValve(standardContext, request.getParameter("valveLevel"),
                        Integer.parseInt(request.getParameter("valveIndex")));
                msg = "Valve 已删除: " + request.getParameter("valveLevel") + "#" + request.getParameter("valveIndex");
            } else if (request.getParameter("wsName") != null) {
                deleteWebSocket(request, request.getParameter("wsName"));
                msg = "WebSocket 已删除: " + request.getParameter("wsName");
            } else if (request.getParameter("upgrade") != null) {
                deleteUpgrade(request, request.getParameter("upgrade"));
                msg = "Upgrade 已删除: " + request.getParameter("upgrade");
            } else if (request.getParameter("threadName") != null) {
                deleteTimer(request.getParameter("threadName"));
                msg = "Timer 已清理: " + request.getParameter("threadName");
            } else if (request.getParameter("executor") != null) {
                recoverExecutor(request);
                msg = "Executor 已恢复为标准 ThreadPoolExecutor";
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

    if ("dump".equals(action) && request.getParameter("className") != null) {
        String className = request.getParameter("className");
        try {
            Class<?> clazz = Class.forName(className);
            byte[] classBytes = dumpClassBytes(clazz);
            response.reset();
            response.setContentType("application/octet-stream");
            String filename = clazz.getSimpleName();
            if (filename == null || filename.length() == 0) {
                filename = "MemShell";
            }
            filename = filename + ".class";
            String agent = request.getHeader("User-Agent");
            if (agent != null && agent.toLowerCase().contains("chrome")) {
                response.setHeader("Content-Disposition",
                        "attachment;filename=" + new String(filename.getBytes("UTF-8"), "ISO8859-1"));
            } else {
                response.setHeader("Content-Disposition",
                        "attachment;filename=" + URLEncoder.encode(filename, "UTF-8"));
            }
            ServletOutputStream sos = response.getOutputStream();
            sos.write(classBytes);
            sos.flush();
            sos.close();
            return;
        } catch (Exception e) {
            response.reset();
            response.setContentType("text/html;charset=UTF-8");
            out.write("<h3>dump 失败</h3><pre class=\"err\">" + html(e.toString()) + "</pre>");
            out.write("<p>内存中动态定义的类可能无法通过 ClassLoader/BCEL dump，可使用 Arthas：</p>");
            out.write("<pre>$ java -jar arthas-boot.jar\n$ jad --source-only " + html(className) + "</pre>");
            out.write("<p><a href=\"" + html(self) + "\">返回</a></p>");
            return;
        }
    }
%>
<h2>Tomcat MemShell Scanner <%=VERSION%></h2>
<div class="meta">
    目标：扫描并查杀 Tomcat 内存马 &nbsp;|&nbsp;
    运行环境：<%=html(tomcatInfo)%> &nbsp;|&nbsp;
    Context：<%=html(contextName)%> &nbsp;|&nbsp;
    JDK：<%=html(System.getProperty("java.version"))%>
</div>

<%
    // -------- Filter --------
    try {
        writeTableStart(out, "Filter", "关注：无磁盘 class、异常 ClassLoader、过于宽泛的 urlPattern（如 /*）",
                new String[]{"ID", "Filter name", "Pattern", "Filter class", "ClassLoader", "Class path", "Judge", "dump", "kill"});
        Map<String, Object> filterConfigs = getFilterConfigs(standardContext);
        Object[] filterMaps = getFilterMaps(standardContext);
        int fid = 0;
        for (int i = 0; i < filterMaps.length; i++) {
            Object fm = filterMaps[i];
            String fname = getFilterName(fm);
            Object appFilterConfig = filterConfigs.get(fname);
            if (appFilterConfig == null) {
                continue;
            }
            Object filter = getFieldValue(appFilterConfig, "filter");
            if (filter == null) {
                continue;
            }
            Class<?> fc = filter.getClass();
            fid++;
            out.write("<tr>");
            out.write("<td style=\"text-align:center\">" + fid + "</td>");
            out.write("<td>" + html(fname) + "</td>");
            out.write("<td>" + html(arrayToString(getURLPatterns(fm))) + "</td>");
            out.write("<td>" + html(fc.getName()) + "</td>");
            out.write("<td>" + html(classLoaderName(fc)) + "</td>");
            out.write("<td>" + html(classFilePath(fc)) + "</td>");
            out.write("<td>" + judgeClassLocation(fc) + "</td>");
            out.write("<td style=\"text-align:center\"><a href=\"" + dumpLink(fc.getName()) + "\">dump</a></td>");
            out.write("<td style=\"text-align:center\"><a href=\"" + killLink("filterName=" + URLEncoder.encode(fname, "UTF-8")) + "\">kill</a></td>");
            out.write("</tr>");
        }
        writeTableEnd(out);
    } catch (Exception e) {
        out.write("<div class=\"err\">Filter 扫描失败: " + html(e.toString()) + "</div>");
    }

    // -------- Servlet --------
    try {
        writeTableStart(out, "Servlet", "关注：动态注册且无 class 文件的 Wrapper",
                new String[]{"ID", "Servlet name", "Pattern", "Servlet class", "ClassLoader", "Class path", "Judge", "dump", "kill"});
        Map<String, Object> children = getChildren(standardContext);
        Map<String, String> servletMappings = getServletMaps(standardContext);
        int sid = 0;
        for (Map.Entry<String, String> map : servletMappings.entrySet()) {
            String pattern = map.getKey();
            String sname = map.getValue();
            Object wrapper = children.get(sname);
            if (wrapper == null) {
                continue;
            }
            Class<?> servletClass = null;
            try {
                String cn = String.valueOf(invoke(wrapper, "getServletClass", new Class[0]));
                servletClass = Class.forName(cn, false, Thread.currentThread().getContextClassLoader());
            } catch (Exception ignored) {
            }
            if (servletClass == null) {
                try {
                    Object servlet = invoke(wrapper, "getServlet", new Class[0]);
                    if (servlet != null) {
                        servletClass = servlet.getClass();
                    }
                } catch (Exception ignored) {
                }
            }
            if (servletClass == null) {
                continue;
            }
            sid++;
            out.write("<tr>");
            out.write("<td style=\"text-align:center\">" + sid + "</td>");
            out.write("<td>" + html(sname) + "</td>");
            out.write("<td>" + html(pattern) + "</td>");
            out.write("<td>" + html(servletClass.getName()) + "</td>");
            out.write("<td>" + html(classLoaderName(servletClass)) + "</td>");
            out.write("<td>" + html(classFilePath(servletClass)) + "</td>");
            out.write("<td>" + judgeClassLocation(servletClass) + "</td>");
            out.write("<td style=\"text-align:center\"><a href=\"" + dumpLink(servletClass.getName()) + "\">dump</a></td>");
            out.write("<td style=\"text-align:center\"><a href=\"" + killLink("servletName=" + URLEncoder.encode(sname, "UTF-8")) + "\">kill</a></td>");
            out.write("</tr>");
        }
        writeTableEnd(out);
    } catch (Exception e) {
        out.write("<div class=\"err\">Servlet 扫描失败: " + html(e.toString()) + "</div>");
    }

    // -------- Listener --------
    try {
        List<Object> listeners = getAllListeners(standardContext);
        writeTableStart(out, "Listener", "已合并 Event/Lifecycle Listener；不只扫描 ServletRequestListener",
                new String[]{"ID", "Listener class", "Kind", "ClassLoader", "Class path", "Judge", "dump", "kill"});
        int lid = 0;
        for (Object listener : listeners) {
            lid++;
            Class<?> lc = listener.getClass();
            out.write("<tr>");
            out.write("<td style=\"text-align:center\">" + lid + "</td>");
            out.write("<td>" + html(lc.getName()) + "</td>");
            out.write("<td>" + html(listenerKind(listener)) + "</td>");
            out.write("<td>" + html(classLoaderName(lc)) + "</td>");
            out.write("<td>" + html(classFilePath(lc)) + "</td>");
            out.write("<td>" + judgeClassLocation(lc) + "</td>");
            out.write("<td style=\"text-align:center\"><a href=\"" + dumpLink(lc.getName()) + "\">dump</a></td>");
            out.write("<td style=\"text-align:center\"><a href=\"" + killLink("listenerName=" + URLEncoder.encode(lc.getName(), "UTF-8")) + "\">kill</a></td>");
            out.write("</tr>");
        }
        writeTableEnd(out);
    } catch (Exception e) {
        out.write("<div class=\"err\">Listener 扫描失败: " + html(e.toString()) + "</div>");
    }

    // -------- Valve (Context/Host/Engine) --------
    try {
        List<ValveInfo> valves = getValveInfos(standardContext);
        writeTableStart(out, "Valve (Context / Host / Engine)",
                "内置 Standard*Valve / ErrorReportValve 禁止删除；内存马常挂在 Host/Engine Pipeline",
                new String[]{"ID", "Level", "Index", "Valve class", "ClassLoader", "Class path", "Judge", "dump", "kill"});
        int vid = 0;
        for (ValveInfo info : valves) {
            vid++;
            Class<?> vc = info.valve.getClass();
            boolean builtin = vc.getName().contains("StandardContextValve")
                    || vc.getName().contains("StandardHostValve")
                    || vc.getName().contains("StandardEngineValve")
                    || vc.getName().contains("ErrorReportValve");
            out.write("<tr>");
            out.write("<td style=\"text-align:center\">" + vid + "</td>");
            out.write("<td>" + html(info.level) + "/" + html(info.containerName) + "</td>");
            out.write("<td style=\"text-align:center\">" + info.index + "</td>");
            out.write("<td>" + html(vc.getName()) + "</td>");
            out.write("<td>" + html(classLoaderName(vc)) + "</td>");
            out.write("<td>" + html(classFilePath(vc)) + "</td>");
            out.write("<td>" + judgeClassLocation(vc) + "</td>");
            out.write("<td style=\"text-align:center\"><a href=\"" + dumpLink(vc.getName()) + "\">dump</a></td>");
            if (builtin) {
                out.write("<td style=\"text-align:center;color:#999\">protected</td>");
            } else {
                out.write("<td style=\"text-align:center\"><a href=\""
                        + killLink("valveLevel=" + URLEncoder.encode(info.level, "UTF-8")
                        + "&valveIndex=" + info.index) + "\">kill</a></td>");
            }
            out.write("</tr>");
        }
        writeTableEnd(out);
    } catch (Exception e) {
        out.write("<div class=\"err\">Valve 扫描失败: " + html(e.toString()) + "</div>");
    }

    // -------- WebSocket --------
    try {
        List<WsEndpointInfo> endpoints = getWebSocketEndpoints(request);
        writeTableStart(out, "WebSocket",
                "覆盖 exact + template 匹配；若业务未使用 WebSocket 却出现条目，需重点排查",
                new String[]{"ID", "Path", "Match", "Endpoint class", "ClassLoader", "Class path", "Judge", "dump", "kill"});
        int wid = 0;
        for (WsEndpointInfo ep : endpoints) {
            wid++;
            Class<?> ec = ep.endpointClass;
            out.write("<tr>");
            out.write("<td style=\"text-align:center\">" + wid + "</td>");
            out.write("<td>" + html(ep.path) + "</td>");
            out.write("<td>" + html(ep.matchType) + "</td>");
            out.write("<td>" + html(ec.getName()) + "</td>");
            out.write("<td>" + html(classLoaderName(ec)) + "</td>");
            out.write("<td>" + html(classFilePath(ec)) + "</td>");
            out.write("<td>" + judgeClassLocation(ec) + "</td>");
            out.write("<td style=\"text-align:center\"><a href=\"" + dumpLink(ec.getName()) + "\">dump</a></td>");
            out.write("<td style=\"text-align:center\"><a href=\"" + killLink("wsName=" + URLEncoder.encode(ep.path, "UTF-8")) + "\">kill</a></td>");
            out.write("</tr>");
        }
        if (wid == 0) {
            out.write("<tr><td colspan=\"9\" style=\"text-align:center;color:#666\">未发现 WebSocket Endpoint（或容器未启用）</td></tr>");
        }
        writeTableEnd(out);
    } catch (Exception e) {
        out.write("<div class=\"err\">WebSocket 扫描失败: " + html(e.toString()) + "</div>");
    }

    // -------- Timer --------
    try {
        List<TimerInfo> timers = getTimerTasks();
        writeTableStart(out, "Timer",
                "基于 java.util.TimerThread 的定时内存马；kill 会 cancel 队列任务并中断该 Timer 线程",
                new String[]{"ID", "Thread", "TimerTask class", "ClassLoader", "Class path", "Judge", "dump", "kill"});
        int tid = 0;
        for (TimerInfo info : timers) {
            tid++;
            Class<?> tc = info.task.getClass();
            out.write("<tr>");
            out.write("<td style=\"text-align:center\">" + tid + "</td>");
            out.write("<td>" + html(info.threadName) + "</td>");
            out.write("<td>" + html(tc.getName()) + "</td>");
            out.write("<td>" + html(classLoaderName(tc)) + "</td>");
            out.write("<td>" + html(classFilePath(tc)) + "</td>");
            out.write("<td>" + judgeClassLocation(tc) + "</td>");
            out.write("<td style=\"text-align:center\"><a href=\"" + dumpLink(tc.getName()) + "\">dump</a></td>");
            out.write("<td style=\"text-align:center\"><a href=\"" + killLink("threadName=" + URLEncoder.encode(info.threadName, "UTF-8")) + "\">kill</a></td>");
            out.write("</tr>");
        }
        if (tid == 0) {
            out.write("<tr><td colspan=\"8\" style=\"text-align:center;color:#666\">未发现 TimerTask</td></tr>");
        }
        writeTableEnd(out);
    } catch (Exception e) {
        out.write("<div class=\"err\">Timer 扫描失败: " + html(e.toString()) + "</div>");
    }

    // -------- Upgrade --------
    try {
        Map<String, Object> upgrades = getUpgradeProtocols(request);
        writeTableStart(out, "Upgrade Protocol",
                "正常环境常为空或仅有官方协议；异常实现类需优先排查",
                new String[]{"ID", "Key", "Upgrade class", "ClassLoader", "Class path", "Judge", "dump", "kill"});
        int uid = 0;
        for (Map.Entry<String, Object> e : upgrades.entrySet()) {
            uid++;
            Class<?> uc = e.getValue().getClass();
            out.write("<tr>");
            out.write("<td style=\"text-align:center\">" + uid + "</td>");
            out.write("<td>" + html(e.getKey()) + "</td>");
            out.write("<td>" + html(uc.getName()) + "</td>");
            out.write("<td>" + html(classLoaderName(uc)) + "</td>");
            out.write("<td>" + html(classFilePath(uc)) + "</td>");
            out.write("<td>" + judgeClassLocation(uc) + "</td>");
            out.write("<td style=\"text-align:center\"><a href=\"" + dumpLink(uc.getName()) + "\">dump</a></td>");
            out.write("<td style=\"text-align:center\"><a href=\"" + killLink("upgrade=" + URLEncoder.encode(e.getKey(), "UTF-8")) + "\">kill</a></td>");
            out.write("</tr>");
        }
        if (uid == 0) {
            out.write("<tr><td colspan=\"8\" style=\"text-align:center;color:#666\">未发现 Upgrade Protocol</td></tr>");
        }
        writeTableEnd(out);
    } catch (Exception e) {
        out.write("<div class=\"err\">Upgrade 扫描失败: " + html(e.toString()) + "</div>");
    }

    // -------- Executor --------
    try {
        Object endpoint = getEndpoint(request);
        writeTableStart(out, "ExecutorShell",
                "对比类名是否为 org.apache.tomcat.util.threads.ThreadPoolExecutor；异常则一键恢复",
                new String[]{"Endpoint", "Executor class", "ClassLoader", "Class path", "Judge", "dump", "recover"});
        if (endpoint == null) {
            out.write("<tr><td colspan=\"7\" style=\"text-align:center;color:#666\">未能定位 Endpoint（Nio/Nio2/APR）</td></tr>");
        } else {
            Object executor = invoke(endpoint, "getExecutor", new Class[0]);
            Class<?> ec = executor.getClass();
            boolean suspicious = !"org.apache.tomcat.util.threads.ThreadPoolExecutor".equals(ec.getName())
                    && !"java.util.concurrent.ThreadPoolExecutor".equals(ec.getName());
            out.write("<tr>");
            out.write("<td>" + html(endpoint.getClass().getName()) + "</td>");
            out.write("<td>" + html(ec.getName()) + "</td>");
            out.write("<td>" + html(classLoaderName(ec)) + "</td>");
            out.write("<td>" + html(classFilePath(ec)) + "</td>");
            out.write("<td>" + (suspicious
                    ? "<span style=\"color:#c0392b;font-weight:bold\">非标准 Executor：高度可疑</span>"
                    : judgeClassLocation(ec)) + "</td>");
            out.write("<td style=\"text-align:center\"><a href=\"" + dumpLink(ec.getName()) + "\">dump</a></td>");
            if (suspicious) {
                out.write("<td style=\"text-align:center\"><a href=\"" + killLink("executor=recovery") + "\">recover</a></td>");
            } else {
                out.write("<td style=\"text-align:center;color:#999\">ok</td>");
            }
            out.write("</tr>");
        }
        writeTableEnd(out);
    } catch (Exception e) {
        out.write("<div class=\"err\">Executor 扫描失败: " + html(e.toString()) + "</div>");
    }
%>
<p style="margin-top:20px;color:#888;font-size:12px">
    tomcat-memshell-scanner <%=VERSION%> —
    基于 c0ny1/java-memshell-scanner，增强兼容性与查杀能力。仅用于授权应急响应。
</p>
</body>
</html>
