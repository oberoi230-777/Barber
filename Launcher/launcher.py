#!/usr/bin/env python3
"""
Portable Retro Gaming Launcher
A beautiful game launcher with 4K support and controller navigation
"""

import pygame
import sys
import os
import json
import subprocess
from pathlib import Path
from typing import List, Dict, Tuple, Optional

# Initialize Pygame
pygame.init()
pygame.joystick.init()

# Constants
WINDOW_TITLE = "Retro Gaming Suite"
FPS = 60

# Colors (Modern dark theme)
COLOR_BG = (15, 15, 25)
COLOR_PANEL = (25, 25, 40)
COLOR_ACCENT = (88, 101, 242)  # Discord-like purple
COLOR_ACCENT_HOVER = (115, 137, 255)
COLOR_TEXT = (255, 255, 255)
COLOR_TEXT_DIM = (150, 150, 160)
COLOR_SUCCESS = (67, 181, 129)
COLOR_WARNING = (250, 166, 26)

class GameSystem:
    """Represents a gaming system/console"""
    
    def __init__(self, name: str, folder: str, extensions: List[str], 
                 emulator: str, icon: str = "🎮"):
        self.name = name
        self.folder = folder
        self.extensions = extensions
        self.emulator = emulator
        self.icon = icon
        self.games: List[Dict] = []
    
    def scan_games(self, roms_path: Path) -> int:
        """Scan for games in the system's ROM folder"""
        self.games = []
        system_path = roms_path / self.folder
        
        if not system_path.exists():
            return 0
        
        for ext in self.extensions:
            for rom_file in system_path.glob(f"*.{ext}"):
                self.games.append({
                    'name': rom_file.stem,
                    'path': str(rom_file),
                    'size': rom_file.stat().st_size
                })
        
        # Sort games alphabetically
        self.games.sort(key=lambda x: x['name'].lower())
        return len(self.games)

class GameLauncher:
    """Main launcher application"""
    
    def __init__(self):
        # Detect script directory (USB drive location)
        self.base_path = Path(__file__).parent.parent.absolute()
        self.roms_path = self.base_path / "ROMs"
        self.emulators_path = self.base_path / "Emulators"
        self.config_path = self.base_path / "Configs"
        
        # Load configuration
        self.systems = self.load_systems()
        
        # Scan for games
        self.scan_all_systems()
        
        # Setup display with 4K support
        self.setup_display()
        
        # Controller setup
        self.controllers = []
        self.setup_controllers()
        
        # UI State
        self.current_view = "systems"  # systems, games
        self.selected_system_idx = 0
        self.selected_game_idx = 0
        self.scroll_offset = 0
        
        # Fonts (scale based on resolution)
        font_scale = self.screen_height / 1080
        self.font_huge = pygame.font.Font(None, int(72 * font_scale))
        self.font_large = pygame.font.Font(None, int(48 * font_scale))
        self.font_medium = pygame.font.Font(None, int(36 * font_scale))
        self.font_small = pygame.font.Font(None, int(24 * font_scale))
        
        # Timing
        self.clock = pygame.time.Clock()
        self.last_input_time = 0
        self.input_delay = 150  # ms between inputs
        
    def setup_display(self):
        """Setup display with 4K support"""
        # Get display info
        display_info = pygame.display.Info()
        
        # Start fullscreen on 4K displays, windowed on smaller
        if display_info.current_w >= 3840:
            self.screen = pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
        else:
            # Windowed mode for development/smaller screens
            window_size = (
                min(1920, display_info.current_w),
                min(1080, display_info.current_h),
            )
            self.screen = pygame.display.set_mode(window_size, pygame.RESIZABLE)
        
        self.screen_width = self.screen.get_width()
        self.screen_height = self.screen.get_height()
        
        pygame.display.set_caption(WINDOW_TITLE)
        
    def setup_controllers(self):
        """Initialize game controllers"""
        for i in range(pygame.joystick.get_count()):
            controller = pygame.joystick.Joystick(i)
            controller.init()
            self.controllers.append(controller)
            print(f"Controller detected: {controller.get_name()}")
    
    def load_systems(self) -> List[GameSystem]:
        """Load system configurations"""
        config_file = self.config_path / "systems.json"
        
        # Default systems if config doesn't exist
        default_systems = [
            {
                "name": "Nintendo Entertainment System",
                "folder": "NES",
                "extensions": ["nes", "unf", "unif"],
                "emulator": "retroarch -L fceumm",
                "icon": "🎮"
            },
            {
                "name": "Super Nintendo",
                "folder": "SNES",
                "extensions": ["smc", "sfc", "fig", "swc"],
                "emulator": "retroarch -L snes9x",
                "icon": "🎮"
            },
            {
                "name": "Nintendo 64",
                "folder": "N64",
                "extensions": ["n64", "z64", "v64"],
                "emulator": "retroarch -L mupen64plus",
                "icon": "🎮"
            },
            {
                "name": "Game Boy / Game Boy Color",
                "folder": "GameBoy",
                "extensions": ["gb", "gbc"],
                "emulator": "retroarch -L gambatte",
                "icon": "🎮"
            },
            {
                "name": "Game Boy Advance",
                "folder": "GBA",
                "extensions": ["gba"],
                "emulator": "retroarch -L mgba",
                "icon": "🎮"
            },
            {
                "name": "Sega Genesis / Mega Drive",
                "folder": "Genesis",
                "extensions": ["md", "bin", "gen", "smd"],
                "emulator": "retroarch -L genesis_plus_gx",
                "icon": "🎮"
            },
            {
                "name": "Sega Master System",
                "folder": "MasterSystem",
                "extensions": ["sms"],
                "emulator": "retroarch -L genesis_plus_gx",
                "icon": "🎮"
            },
            {
                "name": "Sega Game Gear",
                "folder": "GameGear",
                "extensions": ["gg"],
                "emulator": "retroarch -L genesis_plus_gx",
                "icon": "🎮"
            },
            {
                "name": "PlayStation",
                "folder": "PlayStation",
                "extensions": ["cue", "bin", "chd", "pbp"],
                "emulator": "retroarch -L pcsx_rearmed",
                "icon": "🎮"
            },
            {
                "name": "Arcade (MAME)",
                "folder": "Arcade",
                "extensions": ["zip"],
                "emulator": "retroarch -L mame2003_plus",
                "icon": "🕹️"
            },
            {
                "name": "Neo Geo",
                "folder": "NeoGeo",
                "extensions": ["zip"],
                "emulator": "retroarch -L fbneo",
                "icon": "🕹️"
            },
            {
                "name": "Atari 2600",
                "folder": "Atari2600",
                "extensions": ["a26", "bin"],
                "emulator": "retroarch -L stella",
                "icon": "🕹️"
            },
            {
                "name": "Sega Dreamcast",
                "folder": "Dreamcast",
                "extensions": ["cdi", "gdi", "chd"],
                "emulator": "retroarch -L flycast",
                "icon": "🎮"
            },
            {
                "name": "PlayStation Portable",
                "folder": "PSP",
                "extensions": ["iso", "cso", "pbp"],
                "emulator": "retroarch -L ppsspp",
                "icon": "🎮"
            }
        ]
        
        # Save default config if it doesn't exist
        if not config_file.exists():
            self.config_path.mkdir(parents=True, exist_ok=True)
            with open(config_file, 'w') as f:
                json.dump(default_systems, f, indent=2)
        
        # Load systems
        try:
            with open(config_file, 'r') as f:
                systems_data = json.load(f)
        except:
            systems_data = default_systems
        
        return [GameSystem(**system_data) for system_data in systems_data]
    
    def scan_all_systems(self):
        """Scan all systems for games"""
        print("Scanning for games...")
        total_games = 0
        for system in self.systems:
            count = system.scan_games(self.roms_path)
            if count > 0:
                print(f"  {system.name}: {count} games")
                total_games += count
        print(f"Total games found: {total_games}")
    
    def handle_input(self):
        """Handle keyboard and controller input"""
        current_time = pygame.time.get_ticks()
        
        # Input delay to prevent super fast scrolling
        if current_time - self.last_input_time < self.input_delay:
            return
        
        keys = pygame.key.get_pressed()
        
        # Keyboard input should work even when no controller is connected.
        if keys[pygame.K_UP]:
            self.navigate_up()
            self.last_input_time = current_time
            return

        if keys[pygame.K_DOWN]:
            self.navigate_down()
            self.last_input_time = current_time
            return

        if keys[pygame.K_RETURN] or keys[pygame.K_SPACE]:
            self.select_item()
            self.last_input_time = current_time
            return

        if keys[pygame.K_ESCAPE] or keys[pygame.K_BACKSPACE]:
            self.go_back()
            self.last_input_time = current_time
            return

        # Controller input
        for controller in self.controllers:
            hat = controller.get_hat(0) if controller.get_numhats() > 0 else (0, 0)
            axis_y = controller.get_axis(1) if controller.get_numaxes() > 1 else 0

            if hat[1] > 0 or axis_y < -0.5:
                self.navigate_up()
                self.last_input_time = current_time
                return

            if hat[1] < 0 or axis_y > 0.5:
                self.navigate_down()
                self.last_input_time = current_time
                return

            if controller.get_numbuttons() > 0 and controller.get_button(0):
                self.select_item()
                self.last_input_time = current_time
                return

            if controller.get_numbuttons() > 1 and controller.get_button(1):
                self.go_back()
                self.last_input_time = current_time
                return
    
    def navigate_up(self):
        """Navigate up in current menu"""
        if self.current_view == "systems":
            self.selected_system_idx = (self.selected_system_idx - 1) % len(self.systems)
        elif self.current_view == "games":
            system = self.systems[self.selected_system_idx]
            if system.games:
                self.selected_game_idx = (self.selected_game_idx - 1) % len(system.games)
    
    def navigate_down(self):
        """Navigate down in current menu"""
        if self.current_view == "systems":
            self.selected_system_idx = (self.selected_system_idx + 1) % len(self.systems)
        elif self.current_view == "games":
            system = self.systems[self.selected_system_idx]
            if system.games:
                self.selected_game_idx = (self.selected_game_idx + 1) % len(system.games)
    
    def select_item(self):
        """Select current item"""
        if self.current_view == "systems":
            system = self.systems[self.selected_system_idx]
            if system.games:
                self.current_view = "games"
                self.selected_game_idx = 0
        elif self.current_view == "games":
            self.launch_game()
    
    def go_back(self):
        """Go back to previous view"""
        if self.current_view == "games":
            self.current_view = "systems"
        elif self.current_view == "systems":
            self.running = False
    
    def launch_game(self):
        """Launch the selected game"""
        system = self.systems[self.selected_system_idx]
        if not system.games:
            return
        
        game = system.games[self.selected_game_idx]
        
        emulator_cmd = system.emulator.split()
        emulator_path = self.emulators_path / "RetroArch" / f"{emulator_cmd[0]}.exe"

        if not emulator_path.exists():
            print(f"RetroArch executable not found: {emulator_path}")
            return

        cmd_args = emulator_cmd[1:]
        if "-L" in cmd_args:
            core_index = cmd_args.index("-L") + 1
            if core_index < len(cmd_args):
                core_path = self.resolve_core_path(cmd_args[core_index])
                if core_path is None:
                    print(f"Core not found for '{cmd_args[core_index]}'")
                    return
                cmd_args[core_index] = str(core_path)

        cmd = [str(emulator_path)] + cmd_args + [game['path']]
        
        print(f"Launching: {game['name']}")
        print(f"Command: {' '.join(cmd)}")
        
        try:
            # Minimize window and launch emulator
            pygame.display.iconify()
            subprocess.run(cmd, cwd=str(self.emulators_path / "RetroArch"))
            
            # Restore window after game exits
            pygame.display.set_mode((self.screen_width, self.screen_height), 
                                   pygame.RESIZABLE if self.screen_width < 3840 else pygame.FULLSCREEN)
        except Exception as e:
            print(f"Error launching game: {e}")

    def resolve_core_path(self, core_name: str) -> Optional[Path]:
        """Resolve a configured core name to a real libretro DLL."""
        retroarch_path = self.emulators_path / "RetroArch"
        cores_path = retroarch_path / "cores"

        raw_name = core_name.strip().strip('"')
        candidate_path = Path(raw_name)
        direct_candidates = []

        if candidate_path.suffix.lower() == ".dll":
            if candidate_path.is_absolute() and candidate_path.exists():
                return candidate_path

            direct_candidates.extend([
                retroarch_path / candidate_path,
                cores_path / candidate_path.name,
            ])
        else:
            direct_candidates.extend([
                cores_path / f"{raw_name}_libretro.dll",
                cores_path / f"{raw_name}.dll",
            ])

        for candidate in direct_candidates:
            if candidate.exists():
                return candidate

        matches = sorted(cores_path.glob(f"{raw_name}*_libretro.dll"))
        if matches:
            return matches[0]

        return None
    
    def draw_background(self):
        """Draw the background"""
        self.screen.fill(COLOR_BG)
        
        # Add subtle gradient effect
        for i in range(self.screen_height // 4):
            alpha = int(20 * (1 - i / (self.screen_height // 4)))
            s = pygame.Surface((self.screen_width, 4), pygame.SRCALPHA)
            s.fill((COLOR_ACCENT[0], COLOR_ACCENT[1], COLOR_ACCENT[2], alpha))
            self.screen.blit(s, (0, i * 4))
    
    def draw_header(self):
        """Draw the header bar"""
        header_height = int(self.screen_height * 0.1)
        
        # Header background
        pygame.draw.rect(self.screen, COLOR_PANEL, 
                        (0, 0, self.screen_width, header_height))
        
        # Title
        title_text = self.font_huge.render("🎮 RETRO GAMING", True, COLOR_ACCENT)
        title_rect = title_text.get_rect(center=(self.screen_width // 2, header_height // 2))
        self.screen.blit(title_text, title_rect)
        
        # Controller status
        controller_text = f"🎮 {len(self.controllers)} Controller(s)" if self.controllers else "⌨️ Keyboard"
        status = self.font_small.render(controller_text, True, COLOR_TEXT_DIM)
        self.screen.blit(status, (20, header_height - 30))
    
    def draw_systems_view(self):
        """Draw the systems selection view"""
        start_y = int(self.screen_height * 0.15)
        panel_width = int(self.screen_width * 0.8)
        panel_x = (self.screen_width - panel_width) // 2
        item_height = 80
        
        # Title
        title = self.font_large.render("Select System", True, COLOR_TEXT)
        self.screen.blit(title, (panel_x, start_y))
        
        start_y += 80
        
        # Systems list
        for i, system in enumerate(self.systems):
            y = start_y + i * item_height
            
            # Skip if off screen
            if y < 0 or y > self.screen_height:
                continue
            
            # Highlight selected
            is_selected = (i == self.selected_system_idx)
            
            # Draw item panel
            item_rect = pygame.Rect(panel_x, y, panel_width, item_height - 10)
            color = COLOR_ACCENT if is_selected else COLOR_PANEL
            pygame.draw.rect(self.screen, color, item_rect, border_radius=10)
            
            # System name
            name_text = self.font_medium.render(f"{system.icon} {system.name}", True, COLOR_TEXT)
            self.screen.blit(name_text, (panel_x + 20, y + 15))
            
            # Game count
            count_text = self.font_small.render(f"{len(system.games)} games", True, COLOR_TEXT_DIM)
            self.screen.blit(count_text, (panel_x + 20, y + 45))
    
    def draw_games_view(self):
        """Draw the games selection view"""
        system = self.systems[self.selected_system_idx]
        
        start_y = int(self.screen_height * 0.15)
        panel_width = int(self.screen_width * 0.8)
        panel_x = (self.screen_width - panel_width) // 2
        item_height = 70
        
        # Title
        title = self.font_large.render(f"{system.icon} {system.name}", True, COLOR_TEXT)
        self.screen.blit(title, (panel_x, start_y))
        
        # Back hint
        back_text = self.font_small.render("Press ESC or B to go back", True, COLOR_TEXT_DIM)
        self.screen.blit(back_text, (panel_x, start_y + 50))
        
        start_y += 100
        
        # Games list
        visible_items = (self.screen_height - start_y) // item_height
        start_idx = max(0, self.selected_game_idx - visible_items // 2)
        end_idx = min(len(system.games), start_idx + visible_items)
        
        for i in range(start_idx, end_idx):
            game = system.games[i]
            y = start_y + (i - start_idx) * item_height
            
            # Highlight selected
            is_selected = (i == self.selected_game_idx)
            
            # Draw item panel
            item_rect = pygame.Rect(panel_x, y, panel_width, item_height - 10)
            color = COLOR_ACCENT if is_selected else COLOR_PANEL
            pygame.draw.rect(self.screen, color, item_rect, border_radius=10)
            
            # Game name
            name_text = self.font_medium.render(game['name'], True, COLOR_TEXT)
            self.screen.blit(name_text, (panel_x + 20, y + 15))
            
            # File size
            size_mb = game['size'] / (1024 * 1024)
            size_text = self.font_small.render(f"{size_mb:.1f} MB", True, COLOR_TEXT_DIM)
            self.screen.blit(size_text, (panel_x + panel_width - 120, y + 25))
    
    def draw_footer(self):
        """Draw footer with controls"""
        footer_height = 60
        footer_y = self.screen_height - footer_height
        
        # Background
        pygame.draw.rect(self.screen, COLOR_PANEL, 
                        (0, footer_y, self.screen_width, footer_height))
        
        # Controls
        if self.current_view == "systems":
            controls = "↑↓ Navigate  |  Enter/A Select  |  ESC Exit"
        else:
            controls = "↑↓ Navigate  |  Enter/A Launch  |  ESC/B Back"
        
        text = self.font_small.render(controls, True, COLOR_TEXT_DIM)
        text_rect = text.get_rect(center=(self.screen_width // 2, footer_y + footer_height // 2))
        self.screen.blit(text, text_rect)
    
    def run(self):
        """Main game loop"""
        self.running = True
        
        while self.running:
            # Event handling
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    self.running = False
                elif event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_F11:
                        pygame.display.toggle_fullscreen()
            
            # Input handling
            self.handle_input()
            
            # Drawing
            self.draw_background()
            self.draw_header()
            
            if self.current_view == "systems":
                self.draw_systems_view()
            elif self.current_view == "games":
                self.draw_games_view()
            
            self.draw_footer()
            
            # Update display
            pygame.display.flip()
            self.clock.tick(FPS)
        
        pygame.quit()

def main():
    """Main entry point"""
    try:
        launcher = GameLauncher()
        launcher.run()
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        input("Press Enter to exit...")
        sys.exit(1)

if __name__ == "__main__":
    main()
