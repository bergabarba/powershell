<#
.SYNOPSE
    Aplica uma configuracao de rede estatica baseada no usuario logado e um arquivo CSV.
.DESCRICAO
    Versao com captura de erro para diagnosticar falhas na sessao elevada.
    AVISO: Armazenar senhas em texto claro e um risco de seguranca.
    Script desenvolvido para para cpjbauru.local 
.OBSERVACAO IMPORTANTE
    Na linha 23 antes de distribuir o script nas pastas dos usuarios modifique o valor da varivel $Password com o valor correspondente ao usuario.
    Na Linha 67 do script existe um parametro --PrefixLength 24. este valor e o CIDR (prefixo) da mascara de sub-rede. ex: mascara 255.255.255.0
    o valor e 24 e para uma mascara de sub-rede 255.255.255.128 o valor seria 25.
.NOTAS
    Autor: Cesar / contato@bergasoftware.com
    Versao: 1.7 (Captura de Erro)
#>

param(
    [string]$TargetUser
)

# --- INICIO DA AREA DE CONFIGURACAO DE CREDENCIAIS (NAO SEGURO) ---
$Username = "CPJBAURU\administrador"
$Password = "senha-super-forte-kkkk"
# --- FIM DA AREA DE CONFIGURACAO DE CREDENCIAIS ---


# --- INICIO DA LOGICA DE ELEVACAO COM CREDENCIAIS ---
if (-not $TargetUser) {
    $userToPass = $env:USERNAME
    $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential($Username, $SecurePassword)
    
    # Argumentos sao passados de forma com parametros nomeados ex: -noprofile e splatting 
    $ArgumentList = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "`"$($MyInvocation.MyCommand.Path)`"",
        "-TargetUser",
        "$userToPass"
    )

    try {
        Start-Process powershell.exe -Credential $Credential -ArgumentList $ArgumentList
    }
    catch {
        Write-Error "Falha ao iniciar o processo com as credenciais fornecidas."
        Read-Host "Pressione Enter para sair."
    }
    exit
}
# --- FIM DA LOGICA DE ELEVACAO ---


# --- INICIO DA AREA DE CONFIGURACAO DE REDE ---
$InterfaceAlias = "Ethernet" 
$CsvPath = "$PSScriptRoot\usuario-ip.csv"
# --- FIM DA AREA DE CONFIGURACAO DE REDE ---


# --- LOGICA PRINCIPAL DO SCRIPT ---
function Set-StaticIP {
    param($Adapter, $IP, $SubnetMask, $Gateway, $DnsPrimary, $DnsSecondary)
    
    Write-Host "Aplicando configuracoes na placa '$($Adapter.Name)' para o usuario '$TargetUser'..." -ForegroundColor Yellow
    try {
        Remove-NetRoute -InterfaceIndex $Adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceIndex $Adapter.InterfaceIndex -IPAddress $IP -PrefixLength 25 -DefaultGateway $Gateway -ErrorAction Stop
        Set-DnsClientServerAddress -InterfaceIndex $Adapter.InterfaceIndex -ServerAddresses ($DnsPrimary, $DnsSecondary) -ErrorAction Stop
        Write-Host "`nConfiguracao de rede aplicada com sucesso!" -ForegroundColor Green
        Get-NetIPConfiguration -InterfaceIndex $Adapter.InterfaceIndex | Select-Object InterfaceAlias, IPv4Address, IPv4DefaultGateway, DNSServer
    } catch { Write-Error "`nOcorreu um erro critico ao configurar a rede: $_" }
}

# --- EXECUCAO AUTOMATICA ---
Clear-Host
Write-Host "DEBUG (Sessao 2): Sessao elevada iniciada."

# **CORRECAO**: Envolve toda a logica em um bloco try/catch para capturar qualquer erro fatal.
try {
    if (-not $TargetUser) {
        # Esta condicao de erro e a mais provavel.
        throw "A variavel TargetUser esta vazia. O nome de usuario nao foi passado para a sessao elevada."
    }

    if ($TargetUser.Contains('\')) { $CleanTargetUser = $TargetUser.Split('\')[-1] } else { $CleanTargetUser = $TargetUser }

    Write-Host "DEBUG: Nome de usuario recebido: '$TargetUser'"
    Write-Host "DEBUG: Nome de usuario limpo para busca: '$CleanTargetUser'" -ForegroundColor Cyan
    Write-Host "-----------------------------------------------------"

    if (-not (Test-Path $CsvPath)) {
        throw "O arquivo de configuracao '$CsvPath' nao foi encontrado."
    } 

    $csvContent = Import-Csv -Path $CsvPath -Delimiter ';' -Encoding Default
    $userData = $csvContent | Where-Object { $_.Usuario.Trim() -eq $CleanTargetUser }

    if (-not $userData) {
        throw "O usuario '$CleanTargetUser' nao foi encontrado no arquivo CSV."
    } 

    Write-Host "SUCESSO: Usuario '$CleanTargetUser' encontrado no CSV. Prosseguindo..." -ForegroundColor Green
    $adapter = Get-NetAdapter -Name $InterfaceAlias -ErrorAction SilentlyContinue
    if (-not $adapter) { throw "A placa de rede '$InterfaceAlias' nao foi encontrada." }
    if ($adapter.Status -ne 'Up') { throw "A placa de rede '$InterfaceAlias' esta desativada." }
    
    Set-StaticIP -Adapter $adapter -IP $userData.IP -SubnetMask $userData.Mascara -Gateway $userData.Gateway -DnsPrimary $userData.DNS1 -DnsSecondary $userData.DNS2
}
catch {
    # Se qualquer erro fatal (throw) ocorrer no bloco try, ele sera capturado aqui.
    Write-Error "`nERRO FATAL NO SCRIPT:`n$($_.Exception.Message)"
}

Write-Host "`nScript finalizado."
Read-Host "Pressione Enter para fechar esta janela."