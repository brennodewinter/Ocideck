"""Startup contract shared by both native Linux desktop session probes."""
import re

def startup_frame(log):
    """The same fatal startup conditions apply in both native sessions."""
    text = log.read_text()
    if re.search(r'^\S+ (?:ERROR |WARN opstart: nog geen eerste frame na 10 s(?:$| ))',
                 text, re.MULTILINE):
        raise RuntimeError('OciDeck reported a startup error')
    return bool(re.search(r'^\S+ INFO opstart: eerste frame \(\+\d+ ms\)$',
                          text, re.MULTILINE))

