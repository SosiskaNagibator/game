@echo off
setlocal

REM ===== НАСТРОЙКИ =====
REM Ваш ключ OmniRoute
set "ANTHROPIC_AUTH_TOKEN=sk-1a14e1d618e33e5c-e7e116-20f7b2ae"

REM Адрес вашего шлюза OmniRoute (локальный или удаленный)
set "ANTHROPIC_BASE_URL=http://localhost:20128/v1"

REM Отключение экспериментальных бета-функций (по желанию)
set "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1"

REM Модель (раскомментируйте, если шлюз требует явного указания)
set "ANTHROPIC_MODEL=kr/deepseek-3.2"

echo Starting Claude Code via OmniRoute...
claude

endlocal