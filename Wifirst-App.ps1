# Wifirst-App.ps1 â€” fenetre de controle du renouvellement automatique.
param([switch]$NoElevate)
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

$Root    = Split-Path -Parent $PSCommandPath
$Engine  = Join-Path $Root 'Wifirst-Farm.ps1'
$State   = Join-Path $Root 'state'
$Logs    = Join-Path $Root 'logs'
$Compte  = Join-Path $State 'compte.txt'
New-Item -ItemType Directory -Force $State, $Logs | Out-Null

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    exit
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Consoleur {
  [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
}
"@

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Wifirst - acces automatique" Height="560" Width="620"
        WindowStartupLocation="CenterScreen" Background="#101418" ResizeMode="CanMinimize">
  <Window.Resources>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="#E6EDF3"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Background" Value="#1F6FEB"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="14,7"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#0B0F13"/>
      <Setter Property="Foreground" Value="#E6EDF3"/>
      <Setter Property="BorderBrush" Value="#26303A"/>
      <Setter Property="Padding" Value="6,5"/>
      <Setter Property="FontFamily" Value="Consolas"/>
      <Setter Property="IsReadOnly" Value="True"/>
    </Style>
  </Window.Resources>
  <Grid Margin="18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Orientation="Horizontal">
      <Ellipse x:Name="Voyant" Width="12" Height="12" Fill="#8B949E" VerticalAlignment="Center"/>
      <TextBlock x:Name="Statut" Text="Arrete" Margin="8,0,0,0" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center"/>
      <TextBlock x:Name="Minuteur" Text="" Margin="12,0,0,0" Foreground="#8B949E" VerticalAlignment="Center"/>
    </StackPanel>

    <TextBlock Grid.Row="1" Text="Appareil" Margin="0,16,0,4" Foreground="#8B949E"/>
    <TextBox Grid.Row="2" x:Name="Mac" Text="-" Height="28"/>

    <Grid Grid.Row="3" Margin="0,14,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <StackPanel>
        <TextBlock Text="E-mail du compte actif" Foreground="#8B949E"/>
        <TextBox x:Name="Email" Text="-" Height="28" Margin="0,4,0,0"/>
      </StackPanel>
      <Button Grid.Column="1" x:Name="CopierEmail" Content="Copier" VerticalAlignment="Bottom" Margin="8,0,0,0"/>
    </Grid>

    <Grid Grid.Row="4" Margin="0,10,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <StackPanel>
        <TextBlock Text="Mot de passe" Foreground="#8B949E"/>
        <TextBox x:Name="Pass" Text="-" Height="28" Margin="0,4,0,0"/>
      </StackPanel>
      <Button Grid.Column="1" x:Name="CopierPass" Content="Copier" VerticalAlignment="Bottom" Margin="8,0,0,0"/>
    </Grid>

    <TextBox Grid.Row="5" x:Name="Journal" Margin="0,16,0,12" FontSize="11" VerticalScrollBarVisibility="Auto"
             TextWrapping="NoWrap" HorizontalScrollBarVisibility="Auto" Background="#0B0F13"/>

    <StackPanel Grid.Row="6" Orientation="Horizontal">
      <Button x:Name="Demarrer" Content="Demarrer"/>
      <Button x:Name="Arreter" Content="Arreter" Background="#30363D"/>
      <Button x:Name="Portail" Content="Ouvrir le portail" Background="#238636"/>
      <TextBlock x:Name="Info" Text="" Foreground="#8B949E" VerticalAlignment="Center" Margin="8,0,0,0"/>
    </StackPanel>
  </Grid>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xaml))
foreach ($n in 'Voyant','Statut','Minuteur','Mac','Email','Pass','Journal','Demarrer','Arreter','Portail','CopierEmail','CopierPass','Info') {
    Set-Variable -Name $n -Value $win.FindName($n) -Scope Script
}

$script:proc = $null

function Lire-Compte {
    if (-not (Test-Path $Compte)) { $Email.Text = '-'; $Pass.Text = '-'; return }
    $lignes = @{}
    foreach ($l in (Get-Content $Compte -ErrorAction SilentlyContinue)) {
        $i = $l.IndexOf('=')
        if ($i -gt 0) { $lignes[$l.Substring(0, $i)] = $l.Substring($i + 1) }
    }
    $Email.Text = if ($lignes['email']) { $lignes['email'] } else { '-' }
    $Pass.Text  = if ($lignes['password']) { $lignes['password'] } else { '-' }
}

function Journaliser {
    $f = Get-ChildItem (Join-Path $Logs '*.farm.log') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1
    if (-not $f) { return }
    $t = Get-Content $f.FullName -Tail 40 -ErrorAction SilentlyContinue
    if ($t) {
        $Journal.Text = ($t -join "`r`n")
        $Journal.ScrollToEnd()
    }
}

function Maj {
    $adresse = (Get-CimInstance Win32_NetworkAdapter -Filter "NetConnectionID='Wi-Fi'" -ErrorAction SilentlyContinue).MACAddress
    $Mac.Text = if ($adresse) { $adresse } else { '-' }
    Lire-Compte
    Journaliser
    $code = (& curl.exe -k -s -o NUL -w '%{http_code}' --max-time 3 'https://www.google.com/generate_204') | Out-String

    if ($script:proc -and -not $script:proc.HasExited) {
        if ($code.Trim() -eq '204') { $Statut.Text = 'En ligne'; $Voyant.Fill = [Windows.Media.Brushes]::LimeGreen }
        else { $Statut.Text = 'Reconnexion...'; $Voyant.Fill = [Windows.Media.Brushes]::Orange }
        $Demarrer.IsEnabled = $false
        $Arreter.IsEnabled = $true
        $compte = Get-Content $Compte -ErrorAction SilentlyContinue
        if ($compte) {
            $t = ($compte | Where-Object { $_ -like 'cree=*' }) -replace 'cree=', ''
            if ($t) {
                $d = [datetime]$t
                $reste = ($d.AddHours(23.5)) - (Get-Date)
                if ($reste.TotalMinutes -gt 0) { $Minuteur.Text = "renouvellement dans $([math]::Round($reste.TotalMinutes)) min" }
            }
        }
    }
    else {
        $Statut.Text = 'Arrete'
        $Voyant.Fill = [Windows.Media.Brushes]::Gray
        $Demarrer.IsEnabled = $true
        $Arreter.IsEnabled = $false
        $Minuteur.Text = ''
    }
}

function Demarrer-Moteur {
    if ($script:proc -and -not $script:proc.HasExited) { return }
    $script:proc = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Engine`"", '-Force' -WindowStyle Hidden -PassThru
    $Info.Text = 'Demarre'
}

$Demarrer.Add_Click({ Demarrer-Moteur })
$win.Add_Loaded({ Demarrer-Moteur })

$Arreter.Add_Click({
    if ($script:proc -and -not $script:proc.HasExited) { $script:proc.Kill(); $Info.Text = 'Arrete' }
})

$Portail.Add_Click({ Start-Process 'https://portal-front.wifirst.net/' })

$CopierEmail.Add_Click({ if ($Email.Text -ne '-') { [Windows.Clipboard]::SetText($Email.Text) } })
$CopierPass.Add_Click({ if ($Pass.Text -ne '-') { [Windows.Clipboard]::SetText($Pass.Text) } })

$win.Add_Closed({ if ($script:proc -and -not $script:proc.HasExited) { $script:proc.Kill() } })

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({ Maj })
$timer.Start()

$win.ShowDialog() | Out-Null

