[CmdletBinding(SupportsShouldProcess)]
param (
    [string]$PastaBackups = '',
    [int]$NumeroThreads = 4
)

$ErrorActionPreference = 'Continue'

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

$NomeBackup = Read-Host "Digite o nome do backup"
if ($NomeBackup.Length -eq 0) {
    LogWarning -Message "O nome do backup é obrigatório"
    LogInfo -Message "Backup cancelado..."
    exit -1
}

$DataBackup = Read-Host "Digite a data do backup (padrão $(Get-Date -Format 'dd.MM.yyyy'))"
if ($DataBackup.Length -eq 0) {
    $DataBackup = (Get-Date -Format 'dd.MM.yyyy')
}

$LocalBackup = "$PastaBackups\$DataBackup - $NomeBackup"
New-Item $LocalBackup -ItemType Directory
if (Test-Path $LocalBackup) {
    LogInfo -Message "Pasta '$LocalBackup' foi criada com sucesso"
}
else {
    LogWarning -Message "Ocorreu um erro ao criar a pasta de backup!"
    exit -1
}

# Listar o C:\
$PastaC = @(Get-ChildItem -LiteralPath "$env:SystemDrive\")
$PastasSistema = @('Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Users', 'Usuarios', 'Recovery', 'System Volume Information')
$PastaCFiltrada = @($PastaC | Where-Object {$_.Name -notin $PastasSistema})
Write-Host "------- Arquivos de 'C:\' -------" -ForegroundColor 'Yellow'
Write-Output $PastaCFiltrada.Name
Write-Output ""

# Listar a pasta Users
$PastaUsers = @(Get-ChildItem -LiteralPath "$env:SystemDrive\Users")
$PastasSistema = @('Public', "Público")
$PastaUserFiltrada = @($PastaUsers | Where-Object {$_.Name -notin $PastasSistema})

$PastasSistema = @('Saved Games', 'Links', 'Searches', 'Contacts', 'Favorites')
foreach ($user in $PastaUserFiltrada) {
    $PastaUser = @(Get-ChildItem -LiteralPath "$env:SystemDrive\Users\$user")
    $ArquivosUserFiltrados = @($PastaUser | Where-Object {$_.Name -notin $PastasSistema})
    
    Write-Host "------- Arquivos de '$user' -------" -ForegroundColor 'Yellow'
    Write-Output $ArquivosUserFiltrados.Name
    Write-Output ""
}

$option = Read-Host "Prosseguir com o backup? (Y/N)"
while ($option -notin @('Y', 'y', 'N', 'n')) {
    LogWarning -Message "A opção digitada não é válida!"
    $option = Read-Host "Prosseguir com o backup? (Y/N)"
}

if ($option -in @('n', 'N')) {
    LogInfo -Message "Backup cancelado"
    exit 1;
}

# Backup de C:\
$LocalBackupC = "$LocalBackup\C"
New-Item $LocalBackupC -ItemType Directory
if (Test-Path $LocalBackupC) {
    LogInfo -Message "Pasta '$LocalBackupC' foi criada com sucesso"
}
else {
    LogWarning -Message "Ocorreu um erro ao criar a pasta de backup '$LocalBackupC'!"
    exit -1
}

foreach ($arquivo in $PastaCFiltrada) {
    robocopy.exe $env:SystemDrive "$LocalBackupC" $arquivo /mt:$NumeroThreads /e /z /copy:DAT /r:2 /w:3 /xj
}