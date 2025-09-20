# zenpai

A CLI that generates git commit messages with OpenAI.

## Installation

### Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/vutlhari/zenpai/main/install.sh | bash
```

### Manual Install

1. Download the binary for your platform from [releases](https://github.com/vutlhari/zenpai/releases)
2. Make it executable: `chmod +x zenpai`
3. Move to your PATH: `sudo mv zenpai /usr/local/bin/`

## Setup

Set your OpenAI API key:

```bash
export OPENAI_API_KEY="your-api-key-here"
```

## Usage

```bash
# Stage your changes
git add .

# Generate commit message
zenpai
```

## License

MIT
