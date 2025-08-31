<pre>
███╗░░░███╗██████╗░░░██╗██╗  ░█████╗░██████╗░████████╗██╗███╗░░░███╗██╗███████╗███████╗██████╗░
████╗░████║██╔══██╗░██╔╝██║  ██╔══██╗██╔══██╗╚══██╔══╝██║████╗░████║██║╚════██║██╔════╝██╔══██╗
██╔████╔██║██████╔╝██╔╝░██║  ██║░░██║██████╔╝░░░██║░░░██║██╔████╔██║██║░░███╔═╝█████╗░░██████╔╝
██║╚██╔╝██║██╔═══╝░███████║  ██║░░██║██╔═══╝░░░░██║░░░██║██║╚██╔╝██║██║██╔══╝░░██╔══╝░░██╔══██╗
██║░╚═╝░██║██║░░░░░╚════██║  ╚█████╔╝██║░░░░░░░░██║░░░██║██║░╚═╝░██║██║███████╗███████╗██║░░██║
╚═╝░░░░░╚═╝╚═╝░░░░░░░░░░╚═╝  ░╚════╝░╚═╝░░░░░░░░╚═╝░░░╚═╝╚═╝░░░░░╚═╝╚═╝╚══════╝╚══════╝╚═╝░░╚═╝
                                                                                     by Andalik
</pre>

*[English](#english) | [Português (BR)](#português-br)*

---

## English

A sophisticated ZSH script for batch converting MP4 files to HEVC/H.265 format with optimal compression, thermal management, and comprehensive progress tracking. Videos are optimized for maximum Apple device compatibility and streaming performance.

### ✨ Features

- **Efficient HEVC Encoding**: Converts MP4 files to HEVC/H.265 using FFmpeg with libx265
- **Apple Device Optimization**: Uses hvc1 tag for maximum compatibility with Apple devices
- **Streaming Optimization**: Applies faststart flag for immediate streaming capabilities
- **Smart CPU Management**: Configurable CPU limits with optional cpulimit integration
- **Thermal Protection**: Automatic pauses between conversions to prevent overheating
- **Adaptive Presets**: Automatically adjusts encoding presets based on system load
- **Progress Tracking**: Beautiful progress bars and real-time system monitoring
- **Error Handling**: Comprehensive logging and automatic cleanup on interruption
- **File Management**: Smart detection of already converted files to avoid duplicates
- **Flexible Sorting**: Multiple sorting options (alphabetical, file size)

### 🚀 Quick Start

#### Prerequisites

- **FFmpeg** (required)
- **cpulimit** (optional, for precise CPU control)

##### macOS Installation
```bash
brew install ffmpeg
brew install cpulimit  # Optional
```

##### Linux Installation
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install ffmpeg cpulimit

# CentOS/RHEL/Fedora
sudo dnf install ffmpeg cpulimit
```

#### Usage

1. Place the script in a directory containing MP4 files
2. Make it executable:
   ```bash
   chmod +x mp4-optimizer.zsh
   ```
3. Run the converter:
   ```bash
   ./mp4-optimizer.zsh
   ```

### ⚙️ Configuration

Edit the configuration variables at the top of the script:

| Variable | Default | Description |
|----------|---------|-------------|
| `QUALITY_CRF` | 20 | Video quality (18-28, lower = better quality) |
| `PRESET` | "medium" | Encoding speed preset |
| `THREADS` | 0 | Number of threads (0 = auto-detect) |
| `CPU_LIMIT` | 70 | Maximum CPU usage percentage |
| `THERMAL_PAUSE` | 60 | Seconds to pause between conversions |
| `USE_CPULIMIT` | true | Enable precise CPU control |
| `ADAPTIVE_PRESET` | false | Auto-adjust preset based on system load |

#### Quality Settings (CRF)
- **18-22**: Very high quality (larger files)
- **23-28**: Good quality (recommended range)
- **29-35**: Lower quality (smaller files)

#### Encoding Presets
- **ultrafast, superfast, veryfast**: Fast encoding, larger files
- **faster, fast, medium**: Balanced speed/compression (recommended)
- **slow, slower, veryslow**: Best compression, slower encoding

### 📁 File Structure

```
your-directory/
├── mp4-optimizer.zsh             # Main script
├── video1.mp4                    # Original file
├── video1_optimized.mp4          # Converted HEVC file
├── video2.mp4                    # Another original
├── video2_optimized.mp4          # Another converted file
└── mp4-optimizer-logs/           # Error logs directory
    ├── video1_error.log          # Individual error logs
    └── video2_error.log
```

### 🐛 Troubleshooting

#### Common Issues

**FFmpeg not found**
```bash
# Install FFmpeg first
brew install ffmpeg  # macOS
sudo apt install ffmpeg  # Ubuntu/Debian
```

**Permission denied**
```bash
chmod +x mp4-optimizer.zsh
```

**High CPU usage**
- Reduce `CPU_LIMIT` value
- Enable `USE_CPULIMIT` and install cpulimit
- Increase `THERMAL_PAUSE` duration

### 📈 Performance Tips

1. **Optimal CRF**: Start with CRF 20-23 for most content
2. **CPU Management**: Use 70-80% CPU limit for background processing
3. **Thermal Management**: Enable thermal pauses for intensive batch jobs
4. **Storage**: Ensure sufficient disk space (HEVC files are typically 30-50% smaller)

---

## Português (BR)

Um script ZSH sofisticado para conversão em lote de arquivos MP4 para formato HEVC/H.265 com compressão otimizada, gerenciamento térmico e rastreamento abrangente de progresso. Os vídeos são otimizados para máxima compatibilidade com dispositivos Apple e performance de streaming.

### ✨ Funcionalidades

- **Codificação HEVC Eficiente**: Converte arquivos MP4 para HEVC/H.265 usando FFmpeg com libx265
- **Otimização para Dispositivos Apple**: Usa tag hvc1 para máxima compatibilidade com dispositivos Apple
- **Otimização para Streaming**: Aplica flag faststart para capacidades de streaming imediato
- **Gerenciamento Inteligente de CPU**: Limites de CPU configuráveis com integração opcional do cpulimit
- **Proteção Térmica**: Pausas automáticas entre conversões para prevenir superaquecimento
- **Presets Adaptativos**: Ajusta automaticamente os presets de codificação baseado na carga do sistema
- **Rastreamento de Progresso**: Barras de progresso elegantes e monitoramento do sistema em tempo real
- **Tratamento de Erros**: Logging abrangente e limpeza automática em caso de interrupção
- **Gerenciamento de Arquivos**: Detecção inteligente de arquivos já convertidos para evitar duplicatas
- **Ordenação Flexível**: Múltiplas opções de ordenação (alfabética, tamanho do arquivo)

### 🚀 Início Rápido

#### Pré-requisitos

- **FFmpeg** (obrigatório)
- **cpulimit** (opcional, para controle preciso de CPU)

##### Instalação no macOS
```bash
brew install ffmpeg
brew install cpulimit  # Opcional
```

##### Instalação no Linux
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install ffmpeg cpulimit

# CentOS/RHEL/Fedora
sudo dnf install ffmpeg cpulimit
```

#### Uso

1. Coloque o script em um diretório contendo arquivos MP4
2. Torne-o executável:
   ```bash
   chmod +x mp4-optimizer.zsh
   ```
3. Execute o conversor:
   ```bash
   ./mp4-optimizer.zsh
   ```

### ⚙️ Configuração

Edite as variáveis de configuração no topo do script:

| Variável | Padrão | Descrição |
|----------|---------|-----------|
| `QUALITY_CRF` | 20 | Qualidade do vídeo (18-28, menor = melhor qualidade) |
| `PRESET` | "medium" | Preset de velocidade de codificação |
| `THREADS` | 0 | Número de threads (0 = auto-detectar) |
| `CPU_LIMIT` | 70 | Percentual máximo de uso de CPU |
| `THERMAL_PAUSE` | 60 | Segundos de pausa entre conversões |
| `USE_CPULIMIT` | true | Habilitar controle preciso de CPU |
| `ADAPTIVE_PRESET` | false | Auto-ajustar preset baseado na carga do sistema |

#### Configurações de Qualidade (CRF)
- **18-22**: Qualidade muito alta (arquivos maiores)
- **23-28**: Boa qualidade (faixa recomendada)
- **29-35**: Qualidade menor (arquivos menores)

#### Presets de Codificação
- **ultrafast, superfast, veryfast**: Codificação rápida, arquivos maiores
- **faster, fast, medium**: Velocidade/compressão balanceada (recomendado)
- **slow, slower, veryslow**: Melhor compressão, codificação mais lenta

### 📁 Estrutura de Arquivos

```
seu-diretorio/
├── mp4-optimizer.zsh             # Script principal
├── video1.mp4                    # Arquivo original
├── video1_optimized.mp4          # Arquivo HEVC convertido
├── video2.mp4                    # Outro arquivo original
├── video2_optimized.mp4          # Outro arquivo convertido
└── mp4-optimizer-logs/           # Diretório de logs de erro
    ├── video1_error.log          # Logs de erro individuais
    └── video2_error.log
```

### 🐛 Solução de Problemas

#### Problemas Comuns

**FFmpeg não encontrado**
```bash
# Instale o FFmpeg primeiro
brew install ffmpeg  # macOS
sudo apt install ffmpeg  # Ubuntu/Debian
```

**Permissão negada**
```bash
chmod +x mp4-optimizer.zsh
```

**Alto uso de CPU**
- Reduza o valor de `CPU_LIMIT`
- Habilite `USE_CPULIMIT` e instale cpulimit
- Aumente a duração de `THERMAL_PAUSE`

### 📈 Dicas de Performance

1. **CRF Ótimo**: Comece com CRF 20-23 para a maioria dos conteúdos
2. **Gerenciamento de CPU**: Use limite de 70-80% de CPU para processamento em segundo plano
3. **Gerenciamento Térmico**: Habilite pausas térmicas para trabalhos intensivos em lote
4. **Armazenamento**: Garanta espaço suficiente em disco (arquivos HEVC são tipicamente 30-50% menores)

---

## 🤝 Contributing | Contribuindo

Contributions are welcome! Please feel free to submit issues, feature requests, or pull requests.

Contribuições são bem-vindas! Sinta-se livre para enviar issues, solicitações de funcionalidades ou pull requests.

## 📄 License | Licença

This project is open source and available under the [MIT License](LICENSE).

Este projeto é open source e está disponível sob a [Licença MIT](LICENSE).

## 🙏 Acknowledgments | Agradecimentos

- Built with [FFmpeg](https://ffmpeg.org/) - the Swiss Army knife of video processing
- Uses [libx265](https://x265.readthedocs.io/) for HEVC encoding
- Inspired by the need for efficient video compression workflows

---

- Construído com [FFmpeg](https://ffmpeg.org/) - o canivete suíço do processamento de vídeo
- Usa [libx265](https://x265.readthedocs.io/) para codificação HEVC
- Inspirado pela necessidade de fluxos de trabalho eficientes de compressão de vídeo