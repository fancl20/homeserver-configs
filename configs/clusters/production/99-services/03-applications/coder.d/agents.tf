data "kubernetes_secret_v1" "fancl20" {
  metadata {
    name      = "fancl20"
    namespace = "coder"
  }
}

resource "coderd_ai_provider" "zai" {
  type         = "anthropic"
  name         = "zai"
  display_name = "z.ai"
  base_url     = "https://api.z.ai/api/anthropic"

  api_key_wo         = data.kubernetes_secret_v1.fancl20.data["ANTHROPIC_AUTH_TOKEN"]
  api_key_wo_version = 1
}

resource "coderd_agents_model" "glm" {
  ai_provider_id = coderd_ai_provider.zai.id
  model          = "glm-5.3"
  display_name   = "GLM 5.3"
  context_limit  = 1048576

  model_config = jsonencode({
    max_output_tokens = 131072
  })
}

resource "coderd_agents_model" "glm_flash" {
  ai_provider_id = coderd_ai_provider.zai.id
  model          = "glm-5.3-flash"
  display_name   = "GLM 5.3 Flash"
  context_limit  = 1048576
}

resource "coderd_agents_default_model" "glm" {
  organization_id = coderd_agents_model.glm.organization_id
  model_id        = coderd_agents_model.glm.id
}
