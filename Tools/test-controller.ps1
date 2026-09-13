param(
    [switch]$NonInteractive = $false
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "ps-common.ps1")

try {
    Clear-Host
}
catch {
}

Write-Banner -Title "CONTROLLER TEST TOOL" -Subtitle "Launch a small pygame input viewer"

$pythonInfo = Find-PythonCommand
if (-not $pythonInfo) {
    Write-FailLine "Python was not found in PATH."
    Write-InfoLine "Install Python from https://www.python.org/downloads/"
    Pause-IfInteractive -Prompt "Press Enter to exit" -NonInteractive:$NonInteractive
    exit 1
}

Write-OkLine ("Found Python {0} via '{1}'." -f $pythonInfo.Version, $pythonInfo.Command)

if (-not (Ensure-PythonPackage -PythonCommand $pythonInfo.Command -PackageName "pygame" -ModuleName "pygame" -UseUserScope -FallbackPackages @("pygame-ce"))) {
    Write-FailLine "pygame could not be installed automatically."
    Pause-IfInteractive -Prompt "Press Enter to exit" -NonInteractive:$NonInteractive
    exit 1
}

$testScript = @'
import pygame
import sys

pygame.init()
pygame.joystick.init()

screen = pygame.display.set_mode((900, 640))
pygame.display.set_caption("RetroGaming Controller Test")
clock = pygame.time.Clock()
font = pygame.font.Font(None, 32)
small_font = pygame.font.Font(None, 24)

BLACK = (17, 17, 17)
WHITE = (240, 240, 240)
GREEN = (80, 200, 120)
BLUE = (90, 140, 255)
RED = (255, 110, 110)

controllers = []
for index in range(pygame.joystick.get_count()):
    joystick = pygame.joystick.Joystick(index)
    joystick.init()
    controllers.append(joystick)

running = True
while running:
    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            running = False
        elif event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            running = False

    screen.fill(BLACK)
    title = font.render("Controller Test", True, BLUE)
    screen.blit(title, (20, 20))

    if not controllers:
        message = font.render("No controllers detected.", True, RED)
        screen.blit(message, (20, 90))
        hint = small_font.render("Connect a controller and restart this tool.", True, WHITE)
        screen.blit(hint, (20, 130))
    else:
        y = 80
        for idx, joystick in enumerate(controllers):
            name = small_font.render(f"Controller {idx}: {joystick.get_name()}", True, GREEN)
            screen.blit(name, (20, y))
            y += 36

            for axis_id in range(joystick.get_numaxes()):
                value = joystick.get_axis(axis_id)
                axis_text = small_font.render(f"Axis {axis_id}: {value:+0.3f}", True, WHITE)
                screen.blit(axis_text, (40, y))

                bar_x = 270
                bar_width = 220
                pygame.draw.rect(screen, WHITE, (bar_x, y + 4, bar_width, 14), 1)
                fill_width = int((value + 1.0) / 2.0 * bar_width)
                pygame.draw.rect(screen, GREEN, (bar_x, y + 4, fill_width, 14))
                y += 24

            pressed_buttons = [str(button_id) for button_id in range(joystick.get_numbuttons()) if joystick.get_button(button_id)]
            button_label = "Buttons: " + (", ".join(pressed_buttons) if pressed_buttons else "none")
            button_text = small_font.render(button_label, True, WHITE)
            screen.blit(button_text, (40, y))
            y += 28

            for hat_id in range(joystick.get_numhats()):
                hat_value = joystick.get_hat(hat_id)
                hat_text = small_font.render(f"D-Pad {hat_id}: {hat_value}", True, WHITE)
                screen.blit(hat_text, (40, y))
                y += 24

            y += 20

    footer = small_font.render("Press ESC or close the window to exit.", True, WHITE)
    screen.blit(footer, (20, 600))
    pygame.display.flip()
    clock.tick(60)

pygame.quit()
sys.exit(0)
'@

$tempScript = Get-TempPath -Name ("controller-test-{0}.py" -f ([guid]::NewGuid().ToString("N")))

try {
    Set-Content -Path $tempScript -Value $testScript -Encoding UTF8
    Write-InfoLine "Launching controller test window."
    & $pythonInfo.Command $tempScript
    exit $LASTEXITCODE
}
finally {
    Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
}
