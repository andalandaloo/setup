# Mobiadd (Semaphore) Automation Script for Windows

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "   Mobiadd (Semaphore) Automation Script  " -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Function to check if a command exists
function Check-Command {
    param([string]$Cmd)
    if (Get-Command $Cmd -ErrorAction SilentlyContinue) {
        Write-Host "✔ $Cmd is installed." -ForegroundColor Green
    } else {
        Write-Host "Error: $Cmd is not installed." -ForegroundColor Red
        Write-Host "Please install $Cmd and try again."
        exit 1
    }
}

# Function to check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Detect Windows version
$OSVersion = [System.Environment]::OSVersion.Version
Write-Host "Detected OS: Windows $($OSVersion.Major).$($OSVersion.Minor)" -ForegroundColor Cyan

# 1. Check Dependencies
Write-Host "`n[1/6] Checking Dependencies..." -ForegroundColor Cyan
Check-Command "go"
Check-Command "npm"
Check-Command "task"

# 2. Setup & Install Dependencies
Write-Host "`n[2/6] Installing Dependencies..." -ForegroundColor Cyan
task deps
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to install dependencies." -ForegroundColor Red
    exit 1
}

# 3. Build Project
Write-Host "`n[3/6] Building Project..." -ForegroundColor Cyan
task build
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed." -ForegroundColor Red
    exit 1
}
Write-Host "✔ Build successful!" -ForegroundColor Green

# 4. Configuration & Setup
Write-Host "`n[4/6] Configuration & Setup..." -ForegroundColor Cyan
$ConfigFile = "config.json"
$Binary = ".\bin\mobiadd.exe"

if (-not (Test-Path $ConfigFile)) {
    Write-Host "Config file not found. Generating default configuration..." -ForegroundColor Yellow
    
    # Generate random secrets
    function Get-RandomBase64 {
        $Bytes = New-Object Byte[] 32
        [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($Bytes)
        return [Convert]::ToBase64String($Bytes)
    }

    $CookieHash = Get-RandomBase64
    $CookieEncryption = Get-RandomBase64
    $AccessKeyEncryption = Get-RandomBase64

    $ConfigContent = @"
{
    "mysql": {
        "host": "127.0.0.1:3306",
        "user": "root",
        "pass": "",
        "name": "semaphore"
    },
    "dialect": "sqlite",
    "sqlite": {
        "host": "database.sqlite"
    },
    "port": ":3000",
    "interface": "",
    "tmp_path": "/tmp/semaphore",
    "cookie_hash": "$CookieHash",
    "cookie_encryption": "$CookieEncryption",
    "access_key_encryption": "$AccessKeyEncryption",
    "email_alert": false,
    "ldap_enable": false,
    "max_parallel_tasks": 10
}
"@
    Set-Content -Path $ConfigFile -Value $ConfigContent
    Write-Host "✔ Generated $ConfigFile" -ForegroundColor Green

    # Run Migrations
    Write-Host "Running database migrations..." -ForegroundColor Cyan
    & $Binary migrate --config $ConfigFile
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Migration failed." -ForegroundColor Red
        exit 1
    }
    Write-Host "✔ Migrations applied." -ForegroundColor Green

    # Create Admin User
    Write-Host "Creating default admin user..." -ForegroundColor Cyan
    & $Binary user add --admin --login admin --email admin@localhost --password Mobiadd --name "Administrator" --config $ConfigFile
    if ($LASTEXITCODE -ne 0) {
         Write-Host "Failed to create admin user (might already exist)." -ForegroundColor Yellow
    } else {
         Write-Host "✔ Admin user created (Login: admin / Password: Mobiadd)" -ForegroundColor Green
    }

} else {
    Write-Host "✔ Config file exists. Skipping setup." -ForegroundColor Green
}

# 5. System Installation
Write-Host "`n[5/6] System Installation..." -ForegroundColor Cyan
$installChoice = Read-Host "Do you want to install Mobiadd as a Windows service? (y/n)"

if ($installChoice -match "^[Yy]$") {
    if (-not (Test-Administrator)) {
        Write-Host "Installation requires administrator privileges." -ForegroundColor Yellow
        Write-Host "Please run this script as Administrator." -ForegroundColor Yellow
        pause
        exit 1
    }

    Write-Host "Installing Mobiadd to system..." -ForegroundColor Cyan

    # Create installation directory
    $InstallDir = "C:\Program Files\Mobiadd"
    $ConfigDir = "C:\ProgramData\Mobiadd"

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null

    # Copy binary
    Copy-Item $Binary -Destination "$InstallDir\mobiadd.exe" -Force
    Write-Host "✔ Installed binary to $InstallDir" -ForegroundColor Green

    # Copy config and database
    Copy-Item $ConfigFile -Destination "$ConfigDir\config.json" -Force
    if (Test-Path "database.sqlite") {
        Copy-Item "database.sqlite" -Destination "$ConfigDir\database.sqlite" -Force
    }
    Write-Host "✔ Installed config to $ConfigDir" -ForegroundColor Green

    # Update config path in the copied config
    $configContent = Get-Content "$ConfigDir\config.json" -Raw | ConvertFrom-Json
    $configContent.sqlite.host = "$ConfigDir\database.sqlite"
    $configContent | ConvertTo-Json -Depth 10 | Set-Content "$ConfigDir\config.json"

    # Install as Windows Service using NSSM or sc.exe
    Write-Host "Installing Windows service..." -ForegroundColor Cyan
    
    # Using sc.exe (built-in)
    $serviceName = "Mobiadd"
    $serviceDisplayName = "Mobiadd (Semaphore UI)"
    $serviceDescription = "Modern UI for Ansible, Terraform and other DevOps tools"
    $binaryPath = "`"$InstallDir\mobiadd.exe`" server --config `"$ConfigDir\config.json`""

    # Check if service exists
    $existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-Host "Service already exists. Stopping and removing..." -ForegroundColor Yellow
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        sc.exe delete $serviceName
        Start-Sleep -Seconds 2
    }

    # Create service
    sc.exe create $serviceName binPath= $binaryPath start= auto DisplayName= $serviceDisplayName
    sc.exe description $serviceName $serviceDescription
    sc.exe failure $serviceName reset= 86400 actions= restart/60000/restart/60000/restart/60000

    # Start service
    Start-Service -Name $serviceName
    
    Write-Host "✔ Installed and started Windows service" -ForegroundColor Green
    Write-Host "✔ Service status: Get-Service Mobiadd" -ForegroundColor Green
    
    # Add firewall rule
    Write-Host "Adding firewall rule..." -ForegroundColor Cyan
    New-NetFirewallRule -DisplayName "Mobiadd" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow -ErrorAction SilentlyContinue | Out-Null
    Write-Host "✔ Firewall rule added" -ForegroundColor Green

    Write-Host "`n✔ System installation complete!" -ForegroundColor Green
    Write-Host "Access the UI at http://localhost:3000" -ForegroundColor Cyan
    Write-Host "Login: admin / Password: Mobiadd" -ForegroundColor Cyan
    Write-Host "`nService commands:" -ForegroundColor Yellow
    Write-Host "  Start:   Start-Service Mobiadd" -ForegroundColor White
    Write-Host "  Stop:    Stop-Service Mobiadd" -ForegroundColor White
    Write-Host "  Status:  Get-Service Mobiadd" -ForegroundColor White
    Write-Host "  Restart: Restart-Service Mobiadd" -ForegroundColor White

} else {
    Write-Host "Skipping system installation." -ForegroundColor Yellow
    
    # 6. Run Option
    Write-Host "`n[6/6] Execution" -ForegroundColor Cyan
    $choice = Read-Host "Do you want to run the application now? (y/n)"
    if ($choice -match "^[Yy]$") {
        Write-Host "Starting Mobiadd..." -ForegroundColor Cyan
        Write-Host "Access the UI at http://localhost:3000" -ForegroundColor Cyan
        & $Binary server --config $ConfigFile
    } else {
        Write-Host "Done. You can run the app later using: $Binary server --config $ConfigFile" -ForegroundColor Green
    }
}
