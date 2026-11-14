# java-memshell-scanner-new

基于 [c0ny1/java-memshell-scanner](https://github.com/c0ny1/java-memshell-scanner) 的 Tomcat 内存马扫描/查杀 JSP。

将 `tomcat-memshell-scanner.jsp` 部署到目标 Web 应用后访问即可。**仅用于授权应急响应。**

## 当前版本 0.2.0

### 支持类型

| 类型 | 扫描 | 查杀 | 说明 |
|------|------|------|------|
| Filter | ✅ | ✅ | 同步清理 filterDefs / filterMaps / filterConfigs |
| Servlet | ✅ | ✅ | 支持多 urlPattern |
| Listener | ✅ | ✅ | Event + Lifecycle，不限于 ServletRequestListener |
| Valve | ✅ | ✅ | Context / Host / Engine；内置 Valve 受保护 |
| WebSocket | ✅ | ✅ | exact + template 匹配；兼容 javax / jakarta |
| Timer | ✅ | ✅ | TimerThread 队列任务 |
| Upgrade | ✅ | ✅ | AbstractHttp11Protocol.httpUpgradeProtocols |
| ExecutorShell | ✅ | ✅ | 检测非标准 Executor 并可恢复 |

### 兼容性改进

- 反射获取 `StandardContext`（request / ServletContext facade / session 多路径）
- 尽量避免对 Tomcat / WebSocket 类型的硬编码 import，降低 Tomcat 7–10+、javax/jakarta 编译差异
- Filter / Servlet 的 Map 按接口读取，兼容 `HashMap` / `ConcurrentHashMap`
- Listener 兼容 `applicationEventListenersList` 与 `*ListenersObjects` 等字段差异
- class dump：ClassLoader 资源 → BCEL（若存在）→ 失败时提示 Arthas
- 分区 try/catch，单模块失败不中断整页扫描
- 按 class 资源位置给出可疑度提示（无磁盘 class / work 目录等）

### 已知限制

- Agent / `redefineClasses` 型内存马无法通过本 JSP 卸载
- 纯内存 defineClass 且无磁盘资源时，dump 可能失败
- Spring MVC Interceptor / Controller 需另行排查
- 学习/应急产物，请在隔离环境验证后再用于生产
