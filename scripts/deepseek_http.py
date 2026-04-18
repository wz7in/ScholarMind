import os
from typing import Any, Dict, Optional

import requests


SILICONFLOW_ENDPOINT = "https://api.siliconflow.cn/v1/chat/completions"
SILICONFLOW_MODEL = "Pro/deepseek-ai/DeepSeek-V3.2"


def _resolve_api_key() -> str:
    api_key = os.getenv("SILICONFLOW_API_KEY") or os.getenv("AI_API_KEY")
    if not api_key:
        raise RuntimeError(
            "SILICONFLOW_AUTH_ERROR: 缺少 API Key，请设置 SILICONFLOW_API_KEY 或 AI_API_KEY"
        )
    return api_key


def _resolve_proxies() -> Optional[Dict[str, str]]:
    proxy = (
        os.getenv("SCHOLAR_PROXY")
        or os.getenv("HTTP_PROXY")
        or os.getenv("http_proxy")
    )
    if not proxy:
        return None
    return {"http": proxy, "https": proxy}


def _extract_error_text(resp: requests.Response) -> str:
    try:
        payload: Any = resp.json()
    except Exception:
        return (resp.text or "").strip() or f"HTTP {resp.status_code}"

    if isinstance(payload, dict):
        message = payload.get("message")
        data = payload.get("data")
        if message and data:
            return f"{message}: {data}"
        if message:
            return str(message)
    return str(payload)


def call_deepseek_chat(prompt: str, timeout: int = 240) -> str:
    api_key = _resolve_api_key()
    payload = {
        "model": SILICONFLOW_MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
        "temperature": 0.3,
    }

    response = requests.post(
        SILICONFLOW_ENDPOINT,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        json=payload,
        timeout=timeout,
        proxies=_resolve_proxies(),
    )

    if response.status_code in (401, 403):
        raise RuntimeError(
            "SILICONFLOW_AUTH_ERROR: DeepSeek API Key 缺失或无效，请设置 SILICONFLOW_API_KEY 或 AI_API_KEY"
        )
    if response.status_code == 429:
        raise RuntimeError("SILICONFLOW_RATE_LIMIT: 请求过于频繁，请稍后重试")
    if response.status_code in (503, 504):
        raise RuntimeError("SILICONFLOW_OVERLOADED: 模型服务繁忙，请稍后重试")
    if response.status_code >= 400:
        raise RuntimeError(f"SILICONFLOW_HTTP_ERROR: {_extract_error_text(response)}")

    data = response.json()
    choices = data.get("choices", []) if isinstance(data, dict) else []
    if not choices:
        raise RuntimeError("SILICONFLOW_EMPTY_RESPONSE: 返回内容为空")

    message = choices[0].get("message", {}) if isinstance(choices[0], dict) else {}
    content = (message.get("content") or "").strip()
    reasoning = (message.get("reasoning_content") or "").strip()
    final_text = content or reasoning
    if not final_text:
        raise RuntimeError("SILICONFLOW_EMPTY_RESPONSE: 未解析到有效文本")
    return final_text