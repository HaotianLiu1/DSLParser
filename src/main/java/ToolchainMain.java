public class ToolchainMain {
    public static void main(String[] args) {
        ToolchainService service = new ToolchainService();
        ToolchainResult result = service.generateAndValidate(
                "平台需要具备目标监视能力，包含搜索、跟踪和上报。",
                "功能模型");

        System.out.println("success=" + result.success);
        System.out.println("log=" + result.logPath);
        System.out.println("svg=" + result.svgPath);
        if (!result.success) {
            System.err.println("failureReason=" + result.failureReason);
        }
    }
}
