# =============================================================================
# Cloud LLM Service - Groq/OpenAI Compatible API
# Free tier alternative to local Ollama for Render deployment
# =============================================================================

import os
import httpx
from typing import Optional, AsyncGenerator
from dataclasses import dataclass
from orchestration.utils import setup_logging

logger = setup_logging(__name__)


@dataclass
class CloudLLMConfig:
    """Configuration for cloud LLM providers"""
    provider: str = "groq"  # groq, openai, together
    api_key: Optional[str] = None
    base_url: str = "https://api.groq.com/openai/v1"
    model: str = "llama-3.3-70b-versatile"
    embedding_model: str = "nomic-embed-text"
    max_tokens: int = 4096
    temperature: float = 0.7
    
    @classmethod
    def from_env(cls) -> "CloudLLMConfig":
        provider = os.getenv("CLOUD_LLM_PROVIDER", "groq")
        
        base_urls = {
            "groq": "https://api.groq.com/openai/v1",
            "openai": "https://api.openai.com/v1",
            "together": "https://api.together.xyz/v1",
        }
        
        return cls(
            provider=provider,
            api_key=os.getenv("GROQ_API_KEY") or os.getenv("OPENAI_API_KEY"),
            base_url=os.getenv("CLOUD_LLM_BASE_URL", base_urls.get(provider, base_urls["groq"])),
            model=os.getenv("CLOUD_LLM_MODEL", "llama-3.3-70b-versatile"),
            embedding_model=os.getenv("CLOUD_EMBEDDING_MODEL", "nomic-embed-text"),
            max_tokens=int(os.getenv("CLOUD_LLM_MAX_TOKENS", "4096")),
            temperature=float(os.getenv("CLOUD_LLM_TEMPERATURE", "0.7")),
        )


class CloudLLMService:
    """
    Cloud LLM service compatible with OpenAI API format.
    Works with Groq (free tier), OpenAI, Together AI, etc.
    """
    
    def __init__(self, config: Optional[CloudLLMConfig] = None):
        self.config = config or CloudLLMConfig.from_env()
        self._client: Optional[httpx.AsyncClient] = None
        self._initialized = False
    
    async def initialize(self) -> bool:
        """Initialize the cloud LLM client"""
        try:
            if not self.config.api_key:
                logger.warning("No API key configured for cloud LLM")
                return False
            
            self._client = httpx.AsyncClient(
                base_url=self.config.base_url,
                headers={
                    "Authorization": f"Bearer {self.config.api_key}",
                    "Content-Type": "application/json",
                },
                timeout=60.0,
            )
            
            # Test connection
            response = await self._client.get("/models")
            if response.status_code == 200:
                logger.info(f"Cloud LLM initialized with provider: {self.config.provider}")
                self._initialized = True
                return True
            else:
                logger.error(f"Failed to connect to cloud LLM: {response.status_code}")
                return False
                
        except Exception as e:
            logger.error(f"Cloud LLM initialization failed: {e}")
            return False
    
    async def chat(
        self,
        messages: list[dict],
        model: Optional[str] = None,
        temperature: Optional[float] = None,
        max_tokens: Optional[int] = None,
        stream: bool = False,
    ) -> dict:
        """Send chat completion request"""
        if not self._initialized:
            await self.initialize()
        
        payload = {
            "model": model or self.config.model,
            "messages": messages,
            "temperature": temperature or self.config.temperature,
            "max_tokens": max_tokens or self.config.max_tokens,
            "stream": stream,
        }
        
        try:
            response = await self._client.post("/chat/completions", json=payload)
            response.raise_for_status()
            data = response.json()
            
            return {
                "content": data["choices"][0]["message"]["content"],
                "model": data["model"],
                "usage": {
                    "prompt_tokens": data.get("usage", {}).get("prompt_tokens", 0),
                    "completion_tokens": data.get("usage", {}).get("completion_tokens", 0),
                },
            }
        except Exception as e:
            logger.error(f"Cloud LLM chat failed: {e}")
            raise
    
    async def generate(self, prompt: str, **kwargs) -> str:
        """Simple text generation (Ollama-compatible interface)"""
        messages = [{"role": "user", "content": prompt}]
        result = await self.chat(messages, **kwargs)
        return result["content"]
    
    async def stream_chat(
        self,
        messages: list[dict],
        model: Optional[str] = None,
    ) -> AsyncGenerator[str, None]:
        """Stream chat completions"""
        if not self._initialized:
            await self.initialize()
        
        payload = {
            "model": model or self.config.model,
            "messages": messages,
            "temperature": self.config.temperature,
            "max_tokens": self.config.max_tokens,
            "stream": True,
        }
        
        async with self._client.stream("POST", "/chat/completions", json=payload) as response:
            async for line in response.aiter_lines():
                if line.startswith("data: "):
                    data = line[6:]
                    if data == "[DONE]":
                        break
                    try:
                        import json
                        chunk = json.loads(data)
                        if content := chunk["choices"][0].get("delta", {}).get("content"):
                            yield content
                    except:
                        pass
    
    async def list_models(self) -> list[dict]:
        """List available models"""
        if not self._initialized:
            await self.initialize()
        
        try:
            response = await self._client.get("/models")
            response.raise_for_status()
            data = response.json()
            return [
                {"name": m["id"], "size": 0, "modified_at": m.get("created", "")}
                for m in data.get("data", [])
            ]
        except Exception as e:
            logger.error(f"Failed to list models: {e}")
            return []
    
    async def close(self):
        """Close the client"""
        if self._client:
            await self._client.aclose()
            self._client = None
            self._initialized = False


# Singleton instance
_cloud_llm_service: Optional[CloudLLMService] = None


def get_cloud_llm_service() -> CloudLLMService:
    """Get or create cloud LLM service instance"""
    global _cloud_llm_service
    if _cloud_llm_service is None:
        _cloud_llm_service = CloudLLMService()
    return _cloud_llm_service
