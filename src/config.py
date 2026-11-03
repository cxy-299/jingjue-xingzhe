from pathlib import Path
import yaml

def load_config(path: str) -> dict:
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(f"Config not found: {p}")
    with p.open('r', encoding='utf-8') as f:
        config = yaml.safe_load(f)
    # 配置根节点必须是字典，避免 YAML 少换行后在各模块出现难懂的 .get 异常。
    if not isinstance(config, dict):
        raise ValueError("配置根节点应为 YAML 映射，请检查换行、缩进和冒号后的空格")
    return config
