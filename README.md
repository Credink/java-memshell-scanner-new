# java-memshell-scanner-new

基于 [c0ny1/java-memshell-scanner](https://github.com/c0ny1/java-memshell-scanner) 的 Java 中间件内存马扫描/查杀 JSP 集合。**仅用于授权应急响应。**

| 文件 | 目标中间件 |
|------|------------|
| `tomcat-memshell-scanner.jsp` | Tomcat / Spring Boot 内嵌 Tomcat |
| `weblogic-memshell-scanner.jsp` | WebLogic Server |

---

## Tomcat 扫描器（v0.2.1）

部署 `tomcat-memshell-scanner.jsp` 到目标 Web 应用后访问。

### 支持类型

| 类型 | 扫描 | 查杀 | 说明 |
|------|------|------|------|
| Filter | ✅ | ✅ | 同步清理 filterDefs / filterMaps / filterConfigs |
| Servlet | ✅ | ✅ | 支持多 urlPattern |
| Listener | ✅ | ✅ | Event + Lifecycle |
| Valve | ✅ | ✅ | Context / Host / Engine；内置 Valve 受保护 |
| WebSocket | ✅ | ✅ | exact + template；javax / jakarta |
| Timer | ✅ | ✅ | TimerThread 队列任务 |
| Upgrade | ✅ | ✅ | httpUpgradeProtocols |
| ExecutorShell | ✅ | ✅ | 非标准 Executor 可恢复 |

### 兼容性

- 反射多路径获取 `StandardContext`，自动解包 RequestWrapper
- 适配 Tomcat 7–11 / javax & jakarta
- 分区容错；JDK16+ Timer 可能需 `--add-opens`

### 实测

- Tomcat 10.1.34（Jakarta，JDK 21）扫描页 HTTP 200
- Tomcat 9.0.98（javax，JDK 21）扫描页 HTTP 200

---

## WebLogic 扫描器（v0.1.0）

部署 `weblogic-memshell-scanner.jsp` 到 WebLogic 域中的 Web 应用后访问（单独 JSP，不与 Tomcat 版混用）。

### 支持类型

| 类型 | 扫描 | 查杀 | 说明 |
|------|------|------|------|
| Filter | ✅ | ✅ | `FilterManager.filters` + `filterPatternList`，并清理 `cachedClasses` |
| Servlet | ✅ | ✅ | `servletStubs` + `servletMapping`；weblogic/com.bea 内置受保护 |
| Listener | ✅ | ✅ | `EventsManager` 下 request/ctx/session 等列表 |
| cachedClasses | ✅ | — | 展示无磁盘 class 的动态类，辅助研判 |

### 兼容性

- 多路径获取 `WebAppServletContext`（request.context / ServletContext / ExecuteThread.workEntry）
- 反射兼容 10.3.6 / 12c / 14c 常见字段与 `registerFilter` / Stub 差异
- 非 WebLogic 环境会明确提示，避免误用

### 实测（Cloud Agent）

- Docker 镜像 `sutrs/oracle-weblogic:12.2.1.4-dev`（WebLogic **12.2.1.4.0**，JDK 8）
- 扫描页 HTTP 200，Filter/Servlet/Listener/cachedClasses 分段正常
- 动态注册 `ProbeMemFilter` → 扫描可见 → kill → 再次扫描已消失

---

## 已知限制

- Agent / `redefineClasses` 型内存马无法通过 JSP 卸载
- 纯内存 defineClass 且无磁盘资源时，dump 可能失败
- Spring MVC Interceptor / Controller、Jetty / Undertow 等需另案处理
- 学习/应急产物，请在隔离环境验证后再用于生产
