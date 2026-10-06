# ==========================================
# Dedicated Namespace for MCP Tool Servers
# ==========================================

resource "kubernetes_namespace" "mcp" {
  metadata {
    name = "mcp"
    labels = {
      name        = "mcp"
      managed-by  = "terraform"
      description = "in-cluster-mcp-tool-servers"
    }
  }
}
