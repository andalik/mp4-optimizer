#!/bin/zsh

# Configurações
QUALITY_CRF=20                           # Qualidade (18-28, menor = melhor qualidade)
PRESET="medium"                          # Preset de velocidade: ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow
THREADS=0                                # 0 = auto-detectar número de threads
CPU_LIMIT=70                             # Percentual máximo de CPU a utilizar (10-100)
THERMAL_PAUSE=60                         # Pausa em segundos entre conversões (0 = desabilitado)
USE_CPULIMIT=true                        # Usar cpulimit para controle preciso de CPU (true/false)
ADAPTIVE_PRESET=false                    # Ajustar preset baseado na carga do sistema (true/false)

# Constantes de configuração
readonly PROGRESS_BAR_WIDTH=50           # Largura da barra de progresso
readonly MAX_BASENAME_LENGTH=100         # Tamanho máximo permitido para basename de arquivo
readonly MIN_CPU_LIMIT=10                # Limite mínimo de CPU
readonly MAX_CPU_LIMIT=100               # Limite máximo de CPU
readonly MIN_CRF=0                       # Valor mínimo do CRF
readonly MAX_CRF=51                      # Valor máximo do CRF
readonly SUCCESS_THRESHOLD_EXCELLENT=90  # Limite para taxa de sucesso "excelente"
readonly SUCCESS_THRESHOLD_GOOD=70       # Limite para taxa de sucesso "boa"
readonly LOAD_THRESHOLD_HIGH=8           # Limite de carga alta do sistema
readonly LOAD_THRESHOLD_MEDIUM=6         # Limite de carga média do sistema
readonly LOAD_THRESHOLD_LOW=3            # Limite de carga baixa do sistema

# Cores para output
RED='\033[1;31m'                         # Vermelho brilhante
GREEN='\033[1;32m'                       # Verde brilhante
YELLOW='\033[1;33m'                      # Amarelo brilhante
BLUE='\033[1;34m'                        # Azul brilhante
MAGENTA='\033[1;35m'                     # Magenta brilhante
CYAN='\033[1;36m'                        # Ciano brilhante
WHITE='\033[1;37m'                       # Branco brilhante
BLACK='\033[1;30m'                       # Preto brilhante
GRAY='\033[0;90m'                        # Cinza
BOLD='\033[1m'                           # Negrito
DIM='\033[2m'                            # Esmaecido
UNDERLINE='\033[4m'                      # Sublinhado
BLINK='\033[5m'                          # Piscante
REVERSE='\033[7m'                        # Inverso
NC='\033[0m'                             # Reset - Sem cor

# Cores de fundo
BG_BLACK='\033[40m'
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_BLUE='\033[44m'
BG_MAGENTA='\033[45m'
BG_CYAN='\033[46m'
BG_WHITE='\033[47m'

# Contador de arquivos
total_files=0
converted_files=0
skipped_files=0
failed_files=0


# Log de erro para arquivos processados
ERROR_LOG_DIR="./encoder-mp4-hevc_logs"
mkdir -p "$ERROR_LOG_DIR"

# Função de limpeza para sinais
cleanup_on_exit() {
    local exit_code=${1:-1}
    echo ""
    echo "${BOLD}${YELLOW}🛑 INTERROMPIDO:${NC} ${YELLOW}Limpeza em andamento...${NC}"
    
    # Remover arquivos de saída parciais se existirem (com proteção contra race condition)
    local temp_output="$current_output"
    if [[ -n "$temp_output" && -f "$temp_output" ]]; then
        echo "${BOLD}${YELLOW}🗑️ LIMPEZA:${NC} ${YELLOW}Removendo arquivo parcial: $temp_output${NC}"
        rm -f "$temp_output" 2>/dev/null || true
    fi
    
    echo "${BOLD}${GREEN}✓ Limpeza concluída${NC}"
    exit $exit_code
}

# Configurar trap para sinais de terminação
trap 'cleanup_on_exit 1' INT TERM
trap 'cleanup_on_exit 0' EXIT

# Calcular número de threads baseado no limite de CPU
if [[ $THREADS -eq 0 ]]; then
    # Detectar número de CPU cores
    if [[ "$OSTYPE" == darwin* ]]; then
        MAX_CORES=$(sysctl -n hw.ncpu)
    else
        MAX_CORES=$(nproc)
    fi
    
    # Calcular threads baseado no percentual de CPU desejado
    CALCULATED_THREADS=$(( MAX_CORES * CPU_LIMIT / 100 ))
    # Garantir pelo menos 1 thread
    if [[ $CALCULATED_THREADS -lt 1 ]]; then
        CALCULATED_THREADS=1
    fi
    THREADS=$CALCULATED_THREADS
fi

# Função para verificar se cpulimit está instalado
check_cpulimit() {
    if command -v cpulimit >/dev/null 2>&1; then
        return 0
    else
        echo "${BOLD}${YELLOW}⚠️ ATENÇÃO:${NC} ${YELLOW}cpulimit não encontrado.${NC}"
        echo "O cpulimit permite controle preciso do uso de CPU durante as conversões."
        echo -n "Deseja instalar cpulimit via Homebrew? [y/N]: "
        read -r user_choice
        
        case "$user_choice" in
            [yY][eE][sS]|[yY])
                if command -v brew >/dev/null 2>&1; then
                    echo "${CYAN}Instalando cpulimit...${NC}"
                    brew install --quiet cpulimit >/tmp/hevcbatch_brew_cpulimit.log 2>&1
                    # Verificar se a instalação foi bem-sucedida
                    if command -v cpulimit >/dev/null 2>&1; then
                        echo "${BOLD}${GREEN}✅ SUCESSO:${NC} ${GREEN}cpulimit instalado com sucesso.${NC}"
                        return 0
                    else
                        echo "${BOLD}${RED}❌ ERRO:${NC} ${RED}Falha na instalação do cpulimit.${NC}"
                        echo "${DIM}Últimas linhas do log:${NC}"
                        tail -n 10 /tmp/hevcbatch_brew_cpulimit.log 2>/dev/null || echo "${DIM}Log não disponível${NC}"
                        USE_CPULIMIT=false
                        return 1
                    fi
                else
                    echo "${BOLD}${RED}❌ ERRO:${NC} ${RED}Homebrew não encontrado. Desabilitando cpulimit.${NC}"
                    USE_CPULIMIT=false
                    return 1
                fi
                ;;
            *)
                echo "${YELLOW}Continuando sem cpulimit. Usando limitação por threads apenas.${NC}"
                USE_CPULIMIT=false
                return 1
                ;;
        esac
    fi
}



# Função para ajustar preset baseado na carga do sistema
get_adaptive_preset() {
    local load_avg load_int
    
    if [[ "$ADAPTIVE_PRESET" != "true" ]]; then
        echo "$PRESET"
        return
    fi
    
    # Obter carga do sistema
    if [[ "$OSTYPE" == darwin* ]]; then
        load_avg=$(uptime | awk -F'load averages:' '{print $2}' | awk '{print $1}' | tr -d ',')
    else
        load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    fi
    
    # Converter para inteiro (remover ponto decimal)
    load_int=$(printf '%.0f' "$load_avg" 2>/dev/null)
    if [[ -z "$load_int" ]]; then
        load_int=1  # Fallback
    fi
    
    # Ajustar preset baseado apenas na carga do sistema
    if [[ $load_int -gt $LOAD_THRESHOLD_HIGH ]]; then
        echo "slow"      # Sistema sob stress
    elif [[ $load_int -gt $LOAD_THRESHOLD_MEDIUM ]]; then
        echo "medium"    # Sistema moderadamente carregado
    elif [[ $load_int -lt $LOAD_THRESHOLD_LOW ]]; then
        echo "fast"      # Sistema com recursos disponíveis
    else
        echo "$PRESET"   # Usar preset padrão
    fi
}

# Função para validar parâmetros de configuração
validate_config() {
    local errors=0
    
    # Validar CRF (deve estar entre MIN_CRF-MAX_CRF)
    if [[ ! "$QUALITY_CRF" =~ ^[0-9]+$ ]] || [[ $QUALITY_CRF -lt $MIN_CRF ]] || [[ $QUALITY_CRF -gt $MAX_CRF ]]; then
        echo "${BOLD}${RED}❌ ERRO:${NC} ${RED}QUALITY_CRF deve estar entre $MIN_CRF e $MAX_CRF (atual: $QUALITY_CRF)${NC}"
        ((errors++))
    fi
    
    # Validar preset
    valid_presets=("ultrafast" "superfast" "veryfast" "faster" "fast" "medium" "slow" "slower" "veryslow")
    if [[ ! " ${valid_presets[@]} " =~ " ${PRESET} " ]]; then
        echo "${BOLD}${RED}❌ ERRO:${NC} ${RED}PRESET inválido: $PRESET${NC}"
        echo "${DIM}Presets válidos: ${valid_presets[*]}${NC}"
        ((errors++))
    fi
    
    # Validar CPU_LIMIT (deve estar entre MIN_CPU_LIMIT-MAX_CPU_LIMIT)
    if [[ ! "$CPU_LIMIT" =~ ^[0-9]+$ ]] || [[ $CPU_LIMIT -lt $MIN_CPU_LIMIT ]] || [[ $CPU_LIMIT -gt $MAX_CPU_LIMIT ]]; then
        echo "${BOLD}${RED}❌ ERRO:${NC} ${RED}CPU_LIMIT deve estar entre $MIN_CPU_LIMIT e $MAX_CPU_LIMIT (atual: $CPU_LIMIT)${NC}"
        ((errors++))
    fi
    
    # Validar THERMAL_PAUSE (deve ser não-negativo)
    if [[ ! "$THERMAL_PAUSE" =~ ^[0-9]+$ ]] || [[ $THERMAL_PAUSE -lt 0 ]]; then
        echo "${BOLD}${RED}❌ ERRO:${NC} ${RED}THERMAL_PAUSE deve ser um número não-negativo (atual: $THERMAL_PAUSE)${NC}"
        ((errors++))
    fi
    
    # Verificar se ffmpeg está instalado
    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo "${BOLD}${RED}❌ ERRO:${NC} ${RED}FFmpeg não encontrado. Por favor, instale o FFmpeg.${NC}"
        echo "${DIM}Instalar com: brew install ffmpeg${NC}"
        ((errors++))
    fi
    
    # Verificar se há arquivos MP4 para processar
    local mp4_count=0
    while IFS= read -r -d '' file; do
        if [[ "$file" != *"_ffmpeg.mp4" ]]; then
            ((mp4_count++))
            break  # Só precisamos saber se há pelo menos um
        fi
    done < <(find . -name "*.mp4" -type f -print0 2>/dev/null)
    
    if [[ $mp4_count -eq 0 ]]; then
        echo "${BOLD}${YELLOW}⚠️ ATENÇÃO:${NC} ${YELLOW}Nenhum arquivo MP4 encontrado no diretório atual.${NC}"
    fi
    
    if [[ $errors -gt 0 ]]; then
        echo ""
        echo "${BOLD}${RED}❌ Foram encontrados $errors erro(s) de configuração.${NC}"
        echo "${BOLD}${RED}Por favor, corrija os erros antes de continuar.${NC}"
        exit 1
    fi
    
    return 0
}

# Validar configuração antes de prosseguir
validate_config

# Verificar cpulimit se habilitado
if [[ "$USE_CPULIMIT" == "true" ]]; then
    check_cpulimit
fi


# Função para mostrar cabeçalho elegante
show_header() {
    clear
    echo "${BOLD}${BLUE}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo "${BOLD}${BLUE}┃${NC}                        ${BOLD}${MAGENTA}🎥 MP4 Optimizer${NC}                 "
    echo "${BOLD}${BLUE}┃${NC}                     ${CYAN}Otimizador de MP4 para HEVC/H.265${NC}           "
    echo "${BOLD}${BLUE}┡━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩${NC}"
    echo "${BOLD}${BLUE}│${NC} ${WHITE}🔄 Recodifica vídeos MP4 para HEVC/H.265 (libx265), reduzindo o tamanho${NC}"
    echo "${BOLD}${BLUE}│${NC} ${WHITE}    e mantendo a qualidade.${NC}"
    echo "${BOLD}${BLUE}│${NC} ${WHITE}   Preserva o áudio original, assegura compatibilidade com dispositivos${NC}"
    echo "${BOLD}${BLUE}│${NC} ${WHITE}    Apple e otimiza o arquivo para streaming rápido.${NC}"
    echo "${BOLD}${BLUE}│${NC} ${NC}"
    echo "${BOLD}${BLUE}│${NC} ${YELLOW}⚙️  Configurações:${NC}"
    echo "${BOLD}${BLUE}│${NC}     ${WHITE}•${NC} Qualidade (CRF): ${GREEN}$QUALITY_CRF${NC}"
    echo "${BOLD}${BLUE}│${NC}     ${WHITE}•${NC} Preset: ${GREEN}$PRESET${NC}"
    echo "${BOLD}${BLUE}│${NC}     ${WHITE}•${NC} Threads: ${GREEN}$THREADS${NC}"
    echo "${BOLD}${BLUE}│${NC}     ${WHITE}•${NC} Limite CPU: ${GREEN}${CPU_LIMIT}%${NC}"
    echo "${BOLD}${BLUE}│${NC}     ${WHITE}•${NC} Pausa térmica: ${GREEN}${THERMAL_PAUSE}s${NC}"
    if [[ "$USE_CPULIMIT" == "true" ]] && command -v cpulimit >/dev/null 2>&1; then
        echo "${BOLD}${BLUE}│${NC}     ${WHITE}•${NC} Controle CPU: ${GREEN}cpulimit ativo${NC}"
    fi
    echo "${BOLD}${BLUE}└─────────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Log de início
show_header

# Função para solicitar ordem de classificação ao usuário
ask_sort_order() {
    echo "${BOLD}${CYAN}🔤 Como deseja ordenar os arquivos MP4?${NC}" >&2
    echo "" >&2
    echo "  ${WHITE}1)${NC} Ordem alfabética crescente ${DIM}(0-9, A-Z)${NC}" >&2
    echo "  ${WHITE}2)${NC} Ordem alfabética decrescente ${DIM}(Z-A, 9-0)${NC}" >&2
    echo "  ${WHITE}3)${NC} Por tamanho crescente ${DIM}(menor → maior)${NC}" >&2
    echo "  ${WHITE}4)${NC} Por tamanho decrescente ${DIM}(maior → menor)${NC}" >&2
    echo "" >&2
    printf "${BOLD}Escolha uma opção [1-4]:${NC} " >&2
    
    local choice
    read -r choice </dev/tty
    
    case "$choice" in
        1) echo "alpha_asc" ;;
        2) echo "alpha_desc" ;;
        3) echo "size_asc" ;;
        4) echo "size_desc" ;;
        *)
            echo "${YELLOW}⚠️ Opção inválida. Usando ordem alfabética crescente.${NC}" >&2
            echo "alpha_asc"
            ;;
    esac
}

# Função para descobrir e contar arquivos MP4 (otimizada para uma única passagem)
discover_mp4_files() {
    local -a mp4_files=()
    local processable_count=0
    
    echo "${CYAN}🔍 Procurando arquivos MP4...${NC}"
    
    # Usar uma abordagem mais simples e confiável para zsh
    setopt NULL_GLOB
    local all_mp4_files=(*.mp4)
    
    # Se há subdiretórios, procurar neles também
    all_mp4_files+=(*/*.mp4(N))
    all_mp4_files+=(*/*/*.mp4(N))
    
    # Filtrar arquivos já convertidos
    for file in "${all_mp4_files[@]}"; do
        if [[ "$file" != *"_ffmpeg.mp4" ]]; then
            mp4_files+=("$file")
            ((processable_count++))
        fi
    done
    
    unsetopt NULL_GLOB
    
    echo "${GREEN}✓ Busca concluída${NC}"
    
    # Se não há arquivos para processar, retornar
    if [[ ${#mp4_files[@]} -eq 0 ]]; then
        echo ""
        echo "${BOLD}${YELLOW}⚠️ ATENÇÃO:${NC} ${YELLOW}Nenhum arquivo MP4 encontrado para conversão.${NC}"
        echo "${DIM}(Arquivos com sufixo _ffmpeg.mp4 são ignorados pois já foram convertidos)${NC}"
        echo ""
        total_processable=0
        touch /tmp/hevcbatch_files_$$.tmp
        return
    fi
    
    echo "${GREEN}✓ Encontrados ${BOLD}$processable_count${NC}${GREEN} arquivo(s) MP4 para processar${NC}"
    
    # Solicitar ordem de classificação ao usuário
    echo ""
    local sort_order=$(ask_sort_order)
    echo ""
    
    # Ordenar arquivos de acordo com a escolha do usuário
    case "$sort_order" in
        "alpha_asc")
            echo "${CYAN}📂 Ordenando arquivos: ${WHITE}Alfabética crescente${NC}"
            IFS=$'\n' mp4_files=($(printf '%s\n' "${mp4_files[@]}" | sort))
            ;;
        "alpha_desc")
            echo "${CYAN}📂 Ordenando arquivos: ${WHITE}Alfabética decrescente${NC}"
            IFS=$'\n' mp4_files=($(printf '%s\n' "${mp4_files[@]}" | sort -r))
            ;;
        "size_asc")
            echo "${CYAN}📂 Ordenando arquivos: ${WHITE}Tamanho crescente (menor → maior)${NC}"
            # Criar array temporário com tamanho e nome do arquivo
            local -a files_with_size=()
            for file in "${mp4_files[@]}"; do
                local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
                files_with_size+=("${size}:${file}")
            done
            # Ordenar numericamente e extrair apenas os nomes dos arquivos
            IFS=$'\n' mp4_files=($(printf '%s\n' "${files_with_size[@]}" | sort -t: -k1 -n | cut -d: -f2-))
            ;;
        "size_desc")
            echo "${CYAN}📂 Ordenando arquivos: ${WHITE}Tamanho decrescente (maior → menor)${NC}"
            # Criar array temporário com tamanho e nome do arquivo
            local -a files_with_size=()
            for file in "${mp4_files[@]}"; do
                local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
                files_with_size+=("${size}:${file}")
            done
            # Ordenar numericamente reverso e extrair apenas os nomes dos arquivos
            IFS=$'\n' mp4_files=($(printf '%s\n' "${files_with_size[@]}" | sort -t: -k1 -nr | cut -d: -f2-))
            ;;
    esac
    
    echo ""
    
    # Exportar resultados via variáveis globais
    total_processable=$processable_count
    # Salvar lista de arquivos em um arquivo temporário para segunda passagem
    printf '%s\0' "${mp4_files[@]}" > /tmp/hevcbatch_files_$$.tmp
}

# Descobrir arquivos MP4 e contar total
discover_mp4_files

# Contador do arquivo atual
current_file=0

# Função para criar barra de progresso
draw_progress_bar() {
    local current=$1
    local total=$2
    local width=$PROGRESS_BAR_WIDTH
    
    # Proteção contra divisão por zero
    if [[ $total -eq 0 ]]; then
        printf "${CYAN}[%*s]${NC} ${BOLD}0%%${NC} (${BLUE}%d${NC}/${BLUE}%d${NC})\n" $width "" $current $total | tr ' ' '░'
        return
    fi
    
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "${CYAN}["
    printf "%*s" $filled | tr ' ' '█'  # Bloco cheio
    printf "%*s" $empty | tr ' ' '░'   # Bloco vazio
    printf "]${NC} ${BOLD}%d%%${NC} (${BLUE}%d${NC}/${BLUE}%d${NC})\n" $percentage $current $total
}

# Função para animação de texto (efeito typing)
type_text() {
    local text="$1"
    local delay="${2:-0.05}"
    local i
    
    for (( i=0; i<${#text}; i++ )); do
        printf "%c" "${text:$i:1}"
        sleep $delay
    done
    printf "\n"
}

# Função para mostrar spinner de progresso durante operações
show_progress_spinner() {
    local message="$1"
    local pid="$2"
    local delay=0.1
    local frames=('⠋' '⠙' '⠹' '⠻' '⠳' '⠣' '⠃' '⠏' '⠟' '⠷')
    local i=0
    
    printf "${CYAN}%s ${NC}" "$message"
    
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${CYAN}%s ${YELLOW}%c${NC}" "$message" "${frames[i]}"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep $delay
    done
    
    printf "\r${CYAN}%s ${GREEN}✓${NC}\n" "$message"
}

# Função para mostrar efeito de "loading" simples
show_loading_dots() {
    local message="$1"
    local duration="${2:-3}"
    local i
    
    printf "${CYAN}%s${NC}" "$message"
    for (( i=0; i<duration; i++ )); do
        printf "${YELLOW}.${NC}"
        sleep 1
    done
    printf " ${GREEN}concluído!${NC}\n"
}

# Função para mostrar informações do sistema
show_system_info() {
    local cpu_usage="N/A"
    local memory_usage="N/A"
    
    # Obter uso de CPU (média dos últimos 5 segundos)
    if command -v top >/dev/null 2>&1; then
        cpu_usage=$(top -l 1 -n 0 | grep "CPU usage" | awk '{print $3}' | tr -d '%')
    fi
    
    # Obter uso de memória
    if [[ "$OSTYPE" == darwin* ]]; then
        memory_usage=$(vm_stat | awk '/Pages active/ {active=$3} /Pages free/ {free=$3} /Pages wired/ {wired=$3} END {total=(active+free+wired)*4096/1024/1024/1024; used=(active+wired)*4096/1024/1024/1024; printf "%.1f/%.1fGB", used, total}')
    fi
    
    printf "${GRAY}┌───────────────────────────────────────────────────────────────┐${NC}\n"
    printf "${GRAY}│${NC} ${BOLD}${MAGENTA}📊 STATUS DO SISTEMA${NC}\n"
    printf "${GRAY}│${NC}   ${WHITE}•${NC} CPU: ${CYAN}%s%%${NC} | Mem: ${CYAN}%s${NC}\n" "$cpu_usage" "$memory_usage"
    printf "${GRAY}└───────────────────────────────────────────────────────────────┘${NC}\n"
}

# Função para processar um único arquivo
process_single_file() {
    local file="$1"
    local current_file_num="$2"
    local total_files="$3"
    
    # Define arquivo de saída
    local dir=$(dirname "$file")
    local basename=$(basename "$file" .mp4)
    local output="${dir}/${basename}_ffmpeg.mp4"
    current_output="$output"  # Para limpeza em caso de interrupção
    
    # Arquivo de log de erro específico para este arquivo (sanitizar basename)
    local safe_basename=$(echo "$basename" | tr -cd '[:alnum.]._-' | head -c $MAX_BASENAME_LENGTH)
    if [[ -z "$safe_basename" ]]; then
        safe_basename="unknown_file_$(date +%s)"
    fi
    local error_log="$ERROR_LOG_DIR/${safe_basename}_error.log"
    
    # Verifica se já existe
    if [[ -f "$output" ]]; then
        echo "${BLUE}──────────────────────────────────────────────────${NC}"
        echo "${BOLD}${YELLOW}⏭️ PULANDO:${NC} ${WHITE}$basename${NC} ${DIM}(já convertido)${NC}"
        draw_progress_bar $current_file_num $total_files
        ((skipped_files++))
        return 1  # Retorna 1 para indicar que foi pulado
    fi
    
    echo "${BLUE}──────────────────────────────────────────────────${NC}"
    echo "${BOLD}${GREEN}🎥 PROCESSANDO:${NC} ${WHITE}$basename${NC}"
    draw_progress_bar $current_file_num $total_files
    show_system_info
    
    # Obter preset adaptativo
    local current_preset=$(get_adaptive_preset)
    if [[ "$current_preset" != "$PRESET" ]]; then
        echo "   ${BOLD}${CYAN}🔧 PRESET ADAPTATIVO:${NC} ${CYAN}$current_preset${NC} ${DIM}(original: $PRESET)${NC}"
    fi
    
    # Obter informações do arquivo original
    local original_size=$(du -h "$file" | cut -f1)
    
    # Log início da conversão
    echo "$(date): Iniciando conversão de $file para $output" > "$error_log"
    
    # Executar conversão
    local ffmpeg_exit_code=0
    execute_ffmpeg_conversion "$file" "$output" "$error_log" "$current_preset"
    ffmpeg_exit_code=$?
    
    # Log resultado da conversão
    echo "$(date): FFmpeg terminou com código de saída: $ffmpeg_exit_code" >> "$error_log"
    
    # Processar resultado da conversão
    process_conversion_result "$file" "$output" "$error_log" "$ffmpeg_exit_code" "$original_size" "$basename"
    
    current_output=""  # Limpar após processamento
    return 0  # Retorna 0 para indicar que foi processado (convertido)
}

# Função para executar a conversão FFmpeg
execute_ffmpeg_conversion() {
    local input_file="$1"
    local output_file="$2"
    local error_log="$3"
    local current_preset="$4"
    
    # Escapar nomes de arquivos para proteção contra injeção de comandos
    local escaped_input=$(printf '%q' "$input_file")
    local escaped_output=$(printf '%q' "$output_file")
    local escaped_error_log=$(printf '%q' "$error_log")
    
    if [[ "$USE_CPULIMIT" == "true" ]] && command -v cpulimit >/dev/null 2>&1; then
        # Usar cpulimit para controle preciso de CPU
        eval "cpulimit -l $CPU_LIMIT -- ffmpeg -nostdin \
                  -y \
                  -i $escaped_input \
                  -c:v libx265 \
                  -preset $current_preset \
                  -crf $QUALITY_CRF \
                  -pix_fmt yuv420p \
                  -tag:v hvc1 \
                  -c:a copy \
                  -movflags +faststart \
                  -threads $THREADS \
                  -hide_banner \
                  -loglevel error \
                  -stats \
                  $escaped_output 2> >(tee -a $escaped_error_log >&2)"
        return $?
    else
        # Executar conversão normal com threads limitadas
        eval "ffmpeg -nostdin \
              -y \
              -i $escaped_input \
              -c:v libx265 \
              -preset $current_preset \
              -crf $QUALITY_CRF \
              -pix_fmt yuv420p \
              -tag:v hvc1 \
              -c:a copy \
              -movflags +faststart \
              -threads $THREADS \
              -hide_banner \
              -loglevel error \
              -stats \
              $escaped_output 2> >(tee -a $escaped_error_log >&2)"
        return $?
    fi
}

# Função para processar resultado da conversão
process_conversion_result() {
    local input_file="$1"
    local output_file="$2"
    local error_log="$3"
    local exit_code="$4"
    local original_size="$5"
    local basename="$6"
    
    if [[ $exit_code -eq 0 ]]; then
        # Verificar se a conversão foi bem-sucedida
        if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
            # Obter tamanho do novo arquivo
            local new_size=$(du -h "$output_file" | cut -f1)
            
            # Calcular economia (aproximada)
            local original_bytes=$(stat -f%z "$input_file" 2>/dev/null || stat -c%s "$input_file" 2>/dev/null)
            local new_bytes=$(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file" 2>/dev/null)
            
            if [[ -n "$original_bytes" ]] && [[ -n "$new_bytes" ]] && [[ $original_bytes -gt 0 ]]; then
                local savings=$(( (original_bytes - new_bytes) * 100 / original_bytes ))
                echo "   ${BOLD}${GREEN}✅ SUCESSO:${NC} ${CYAN}$original_size${NC} → ${CYAN}$new_size${NC} ${BOLD}${GREEN}(economia: ${savings}%)${NC}"
                echo "$(date): Conversão bem-sucedida. Economia: ${savings}%" >> "$error_log"
            else
                echo "   ${BOLD}${GREEN}✅ SUCESSO:${NC} ${CYAN}$original_size${NC} → ${CYAN}$new_size${NC}"
                echo "$(date): Conversão bem-sucedida." >> "$error_log"
            fi
            
            # Preservar timestamps do arquivo original
            touch -r "$input_file" "$output_file"
            
            # Remover log de erro se conversão bem-sucedida
            rm -f "$error_log"
            
            ((converted_files++))
        else
            echo "   ${BOLD}${RED}❌ ERRO:${NC} ${RED}arquivo de saída vazio ou não criado${NC}"
            echo "$(date): ERRO - Arquivo de saída vazio ou não criado" >> "$error_log"
            echo "   ${DIM}Log de erro: $error_log${NC}"
            [[ -f "$output_file" ]] && rm -f "$output_file"
            ((failed_files++))
        fi
    else
        echo "   ${BOLD}${RED}❌ ERRO:${NC} ${RED}falha na conversão (código: $exit_code)${NC}"
        echo "$(date): ERRO - FFmpeg falhou com código $exit_code" >> "$error_log"
        echo "   ${DIM}Log de erro: $error_log${NC}"
        [[ -f "$output_file" ]] && rm -f "$output_file"
        ((failed_files++))
    fi
}

# Função para pausa térmica
thermal_pause() {
    local current_file="$1"
    local total_processable="$2"
    
    if [[ $THERMAL_PAUSE -gt 0 ]] && [[ $current_file -lt $total_processable ]]; then
        echo "${BOLD}${YELLOW}🌡️ PAUSA TÉRMICA:${NC} ${YELLOW}aguardando resfriamento...${NC}"
        
        # Contador visual regressivo
        for (( countdown=$THERMAL_PAUSE; countdown>0; countdown-- )); do
            printf "\r${YELLOW}⏳ Aguardando: ${BOLD}%02d${NC}${YELLOW}s restantes${NC}" $countdown
            sleep 1
        done
        printf "\r${GREEN}✓ Pausa concluída!                    ${NC}\n"
    fi
}

# Processar todos os arquivos MP4 descobertos
while IFS= read -r -d '' file; do
    # Arquivos já filtrados na função discover_mp4_files()
    ((total_files++))
    ((current_file++))
    
    # Processar arquivo usando função dedicada
    process_single_file "$file" "$current_file" "$total_processable"
    local file_processed=$?
    
    # Pausa térmica apenas se o arquivo foi realmente convertido (não pulado)
    if [[ $file_processed -eq 0 ]]; then
        thermal_pause "$current_file" "$total_processable"
    fi
    
    echo ""
    
done < /tmp/hevcbatch_files_$$.tmp

# Limpar arquivo temporário
rm -f /tmp/hevcbatch_files_$$.tmp

# Função para mostrar relatório final aprimorado
show_final_report() {
    local success_rate=0
    local total_processed=$((converted_files + failed_files))
    
    if [[ $total_processed -gt 0 ]]; then
        success_rate=$((converted_files * 100 / total_processed))
    fi
    
    echo ""
    echo "${BOLD}${BLUE}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo "${BOLD}${BLUE}┃${NC}                        ${BOLD}${MAGENTA}📊 RELATÓRIO FINAL${NC}"
    echo "${BOLD}${BLUE}┡━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩${NC}"
    echo "${BOLD}${BLUE}┃${NC}"
    echo "${BOLD}${BLUE}┃${NC}   ${WHITE}📁 Total de arquivos processados:${NC} ${BOLD}${CYAN}$total_files${NC}"
    echo "${BOLD}${BLUE}┃${NC}"
    echo "${BOLD}${BLUE}┃${NC}   ${GREEN}✓${NC} ${BOLD}${GREEN}Convertidos com sucesso:${NC} ${BOLD}${GREEN}$converted_files${NC}"
    echo "${BOLD}${BLUE}┃${NC}   ${YELLOW}⏭️${NC} ${BOLD}${YELLOW}Arquivos já convertidos:${NC} ${BOLD}${YELLOW}$skipped_files${NC}"
    echo "${BOLD}${BLUE}┃${NC}   ${RED}❌${NC} ${BOLD}${RED}Falhas na conversão:${NC} ${BOLD}${RED}$failed_files${NC}"
    echo "${BOLD}${BLUE}┃${NC}"
    
    # Gráfico ASCII simples de taxa de sucesso
    if [[ $success_rate -ge $SUCCESS_THRESHOLD_EXCELLENT ]]; then
        local status_color="$GREEN"
        local status_icon="🎆"
        local status_text="EXCELENTE"
    elif [[ $success_rate -ge $SUCCESS_THRESHOLD_GOOD ]]; then
        local status_color="$YELLOW"
        local status_icon="😊"
        local status_text="BOM"
    else
        local status_color="$RED"
        local status_icon="⚠️"
        local status_text="ATENÇÃO"
    fi
    
    echo "${BOLD}${BLUE}┃${NC}   ${BOLD}Taxa de Sucesso: ${status_color}${success_rate}% ${status_icon} ${status_text}${NC}"
    echo "${BOLD}${BLUE}┃${NC}"
    
    # Barra visual da taxa de sucesso
    local bar_width=40
    local filled_success=$((success_rate * bar_width / 100))
    local empty_success=$((bar_width - filled_success))
    
    echo -n "${BOLD}${BLUE}┃${NC}   Progresso: ${status_color}["
    printf "%*s" $filled_success | tr ' ' '█'
    printf "%*s" $empty_success | tr ' ' '░'
    echo "] ${success_rate}%${NC}"
    
    echo "${BOLD}${BLUE}┃${NC}"
    echo "${BOLD}${BLUE}└─────────────────────────────────────────────────────────────────────────┘${NC}"
    
    # Mensagem final baseada no resultado
    if [[ $converted_files -gt 0 ]]; then
        echo ""
        echo "${BOLD}${GREEN}🎉 Conversão concluída! Os arquivos H.265 foram salvos com sufixo '_ffmpeg.mp4'${NC}"
    elif [[ $skipped_files -gt 0 ]]; then
        echo ""
        echo "${BOLD}${YELLOW}📝 Todos os arquivos já foram convertidos anteriormente.${NC}"
    else
        echo ""
        echo "${BOLD}${RED}⚠️ Nenhum arquivo foi convertido. Verifique se há arquivos MP4 no diretório.${NC}"
    fi
    echo ""
}

# Chamada do relatório final
show_final_report