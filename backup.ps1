[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$PastaBackups,

    [ValidateRange(1, 128)]
    [int]$NumeroThreads = 4
)

$ErrorActionPreference = 'Continue'

# ----------------------------------------------------------------------------
# Configuração: itens que NÃO entram no backup
# ----------------------------------------------------------------------------
# Raiz do C:\
$ExcluirRaiz = @('Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Users', 'Usuarios', 'Recovery', 'System Volume Information', '$Recycle.Bin', 'PerfLogs')
# Exemplo de lista específica da máquina de testes (descomente e ajuste se precisar):
# $ExcluirRaiz += @('Adjustment Program', 'Elgin', 'ESD', 'HP_LaserJet_Pro_MFP_M426f-M427f', 'inetpub', 'LJP1100_P1560_P1600_Full_Solution', 'Log Files', 'M1130MFP_M1210MFP_Full_Solution', 'NVIDIA', 'Seagull', 'VM-Discos', 'ZD10-6-26-28275', 'HPLJP1000_P1500_Series.log', 'rufus-4.15.exe')

# Pastas dentro de C:\Users
$ExcluirUsuarios = @('Public', 'Público')

# Itens dentro de cada perfil de usuário
$ExcluirPerfil = @('Saved Games', 'Links', 'Searches', 'Contacts', 'Favorites')

# ----------------------------------------------------------------------------
# Funções
# ----------------------------------------------------------------------------
function LogInfo {
    param ($Message)
    $dataHora = Get-Date -Format 'dd/MM/yyyy HH:mm'
    Write-Host "[$dataHora] [INFO] $Message" -ForegroundColor Blue
}

function LogWarning {
    param ($Message)
    $dataHora = Get-Date -Format 'dd/MM/yyyy HH:mm'
    Write-Host "[$dataHora] [WARNING] $Message" -ForegroundColor Yellow
}

function LogError {
    param ($Message)
    $dataHora = Get-Date -Format 'dd/MM/yyyy HH:mm'
    Write-Host "[$dataHora] [ERROR] $Message" -ForegroundColor Red
}

# Retorna $true se a pasta informada é (ou contém) a pasta de destino do backup
function Test-ContemDestino {
    param ([string]$Pasta)
    $p = $Pasta.TrimEnd('\')
    return ($script:LocalBackupNorm -ieq $p) -or $script:LocalBackupNorm.StartsWith("$p\", [System.StringComparison]::OrdinalIgnoreCase)
}

# Lista os itens de uma pasta aplicando os filtros (exclusões, junctions e destino)
function Get-ItensBackup {
    param (
        [string]$Caminho,
        [string[]]$Excluir
    )
    foreach ($item in @(Get-ChildItem -LiteralPath $Caminho -ErrorAction SilentlyContinue)) {
        if ($item.Name -in $Excluir) { continue }
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
        if ($item.PSIsContainer -and (Test-ContemDestino -Pasta $item.FullName)) {
            LogWarning -Message "'$($item.FullName)' contém a pasta de backup e será ignorada"
            continue
        }
        $item
    }
}

function Test-NomeValido {
    param ([string]$Nome)
    return $Nome.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -eq -1
}

# Copia um arquivo ou pasta com robocopy. Retorna o código de saída do robocopy.
function Copiar-Item {
    param (
        [System.IO.FileSystemInfo]$Item,
        [string]$DestinoBase
    )

    $opcoes = @(
        '/E', '/COPY:DAT', '/DCOPY:DAT',
        '/R:1', '/W:1',
        "/MT:$NumeroThreads",
        '/XJ', '/NP',
        '/XD', $script:LocalBackup,
        "/UNILOG+:$script:ArquivoLog"
    )
    if ($script:EhAdmin) { $opcoes += '/B' }

    if ($Item.PSIsContainer) {
        $parametros = @($Item.FullName, (Join-Path $DestinoBase $Item.Name)) + $opcoes
    }
    else {
        # Arquivo solto: origem = pasta do arquivo, destino = pasta base, filtro = nome do arquivo
        $parametros = @($Item.DirectoryName, $DestinoBase, $Item.Name) + $opcoes
    }

    & robocopy @parametros | Out-Null
    return $LASTEXITCODE
}

# ----------------------------------------------------------------------------
# Entrada do usuário
# ----------------------------------------------------------------------------
$EhAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $EhAdmin) {
    LogWarning -Message "O script não está sendo executado como administrador. Perfis de outros usuários e arquivos protegidos podem não ser copiados."
}

$NomeBackup = (Read-Host "Digite o nome do backup").Trim()
if ($NomeBackup.Length -eq 0) {
    LogWarning -Message "O nome do backup é obrigatório"
    LogInfo -Message "Backup cancelado..."
    exit -1
}

$DataBackup = (Read-Host "Digite a data do backup (padrão $(Get-Date -Format 'dd.MM.yyyy'))").Trim()
if ($DataBackup.Length -eq 0) {
    $DataBackup = (Get-Date -Format 'dd.MM.yyyy')
}

if (-not (Test-NomeValido -Nome $NomeBackup) -or -not (Test-NomeValido -Nome $DataBackup)) {
    LogWarning -Message "O nome ou a data contém caracteres inválidos para nome de pasta (\ / : * ? `" < > |)"
    LogInfo -Message "Backup cancelado..."
    exit -1
}

$LocalBackup = Join-Path $PastaBackups "$DataBackup - $NomeBackup"
$LocalBackupNorm = $LocalBackup.TrimEnd('\')
$ArquivoLog = Join-Path $LocalBackup 'backup.log'

if (Test-Path -LiteralPath $LocalBackup) {
    LogWarning -Message "A pasta '$LocalBackup' já existe!"
    LogInfo -Message "Backup cancelado..."
    exit -1
}

# ----------------------------------------------------------------------------
# Montagem do plano de backup
# ----------------------------------------------------------------------------
$Plano = @()

# C:\
$ItensC = @(Get-ItensBackup -Caminho "$env:SystemDrive\" -Excluir $ExcluirRaiz)
Write-Host "------- Arquivos de 'C:\' -------" -ForegroundColor 'Yellow'
Write-Output $ItensC.Name
Write-Output ""
foreach ($item in $ItensC) {
    $Plano += [pscustomobject]@{ Item = $item; DestinoBase = (Join-Path $LocalBackup 'C') }
}

# C:\Users\<usuario>
$Usuarios = @(Get-ChildItem -LiteralPath "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin $ExcluirUsuarios })

foreach ($user in $Usuarios) {
    $ItensUser = @(Get-ItensBackup -Caminho $user.FullName -Excluir $ExcluirPerfil)

    Write-Host "------- Arquivos de '$($user.Name)' -------" -ForegroundColor 'Yellow'
    Write-Output $ItensUser.Name
    Write-Output ""

    foreach ($item in $ItensUser) {
        $Plano += [pscustomobject]@{ Item = $item; DestinoBase = (Join-Path $LocalBackup "Users\$($user.Name)") }
    }
}

if ($Plano.Count -eq 0) {
    LogWarning -Message "Nenhum item encontrado para backup"
    exit 1
}

# ----------------------------------------------------------------------------
# Confirmação
# ----------------------------------------------------------------------------
$option = Read-Host "Prosseguir com o backup? (Y/N)"
while ($option -notin @('Y', 'N')) {
    LogWarning -Message "A opção digitada não é válida!"
    $option = Read-Host "Prosseguir com o backup? (Y/N)"
}

if ($option -eq 'N') {
    LogInfo -Message "Backup cancelado"
    exit 1
}

# ----------------------------------------------------------------------------
# Criação da pasta de destino
# ----------------------------------------------------------------------------
try {
    New-Item -Path $LocalBackup -ItemType Directory -ErrorAction Stop | Out-Null
    LogInfo -Message "Pasta '$LocalBackup' foi criada com sucesso"
}
catch {
    LogError -Message "Ocorreu um erro ao criar a pasta de backup '$LocalBackup': $($_.Exception.Message)"
    exit -1
}

# ----------------------------------------------------------------------------
# Cópia
# ----------------------------------------------------------------------------
$Falhas = @()
$Total = $Plano.Count
$Atual = 0
$Inicio = Get-Date

foreach ($entrada in $Plano) {
    $Atual++
    $origem = $entrada.Item.FullName
    LogInfo -Message "[$Atual/$Total] Copiando '$origem'..."

    $codigo = Copiar-Item -Item $entrada.Item -DestinoBase $entrada.DestinoBase

    # Robocopy: 0-7 = sucesso (com ou sem arquivos copiados), 8 ou mais = falhas
    if ($codigo -ge 8) {
        LogError -Message "Falha ao copiar '$origem' (código robocopy: $codigo)"
        $Falhas += $origem
    }
}

# ----------------------------------------------------------------------------
# Resumo
# ----------------------------------------------------------------------------
$Duracao = (Get-Date) - $Inicio
LogInfo -Message ("Backup finalizado em {0:hh\:mm\:ss}" -f $Duracao)
LogInfo -Message "Log detalhado: $ArquivoLog"

if ($Falhas.Count -gt 0) {
    LogWarning -Message "$($Falhas.Count) item(ns) com falha:"
    $Falhas | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    exit 2
}

LogInfo -Message "Backup concluído sem erros"
exit 0