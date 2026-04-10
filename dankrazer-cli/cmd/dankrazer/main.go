package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/spf13/cobra"
	"github.com/zachatrocern/dankrazer/internal/razer"
)

func main() {
	root := &cobra.Command{
		Use:   "dankrazer",
		Short: "Control Razer devices via OpenRazer",
	}

	root.AddCommand(
		listCmd(),
		infoCmd(),
		brightnessCmd(),
		effectCmd(),
		dpiCmd(),
		versionCmd(),
		statusCmd(),
	)

	if err := root.Execute(); err != nil {
		os.Exit(1)
	}
}

func withClient(fn func(*razer.Client) error) error {
	c, err := razer.NewClient()
	if err != nil {
		return fmt.Errorf("failed to connect to OpenRazer daemon: %w", err)
	}
	defer c.Close()
	return fn(c)
}

func resolveDevice(c *razer.Client, selector string) (*razer.Device, error) {
	serials, err := c.DeviceSerials()
	if err != nil {
		return nil, err
	}
	if len(serials) == 0 {
		return nil, fmt.Errorf("no Razer devices found")
	}

	// If no selector, use first device
	if selector == "" {
		return c.Device(serials[0]), nil
	}

	// Try by index
	if idx, err := strconv.Atoi(selector); err == nil && idx >= 0 && idx < len(serials) {
		return c.Device(serials[idx]), nil
	}

	// Try by serial
	for _, s := range serials {
		if s == selector {
			return c.Device(s), nil
		}
	}

	// Try by name substring (case-insensitive)
	for _, s := range serials {
		dev := c.Device(s)
		name, _ := dev.Name()
		if strings.Contains(strings.ToLower(name), strings.ToLower(selector)) {
			return dev, nil
		}
	}

	return nil, fmt.Errorf("device not found: %s", selector)
}

// --- Commands ---

func versionCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Show daemon version",
		RunE: func(cmd *cobra.Command, args []string) error {
			return withClient(func(c *razer.Client) error {
				v, err := c.DaemonVersion()
				if err != nil {
					return err
				}
				fmt.Println(v)
				return nil
			})
		},
	}
}

func listCmd() *cobra.Command {
	var jsonOut bool
	cmd := &cobra.Command{
		Use:   "list",
		Short: "List connected Razer devices",
		RunE: func(cmd *cobra.Command, args []string) error {
			c, err := razer.NewClient()
			if err != nil {
				// Daemon not available — return empty result instead of error
				if jsonOut {
					fmt.Println("[]")
					return nil
				}
				fmt.Println("OpenRazer daemon not available")
				return nil
			}
			defer c.Close()

			devices, err := c.Devices()
			if err != nil {
				if jsonOut {
					fmt.Println("[]")
					return nil
				}
				return err
			}
			if len(devices) == 0 {
				if jsonOut {
					fmt.Println("[]")
					return nil
				}
				fmt.Println("No Razer devices found")
				return nil
			}

			if jsonOut {
				infos := make([]razer.DeviceInfo, len(devices))
				for i, d := range devices {
					infos[i] = d.Info()
				}
				return json.NewEncoder(os.Stdout).Encode(infos)
			}

			for i, d := range devices {
				name, _ := d.Name()
				dtype, _ := d.Type()
				brightness, _ := d.Brightness()
				fmt.Printf("[%d] %s (%s) serial=%s brightness=%.0f%%\n",
					i, name, dtype, d.Serial, brightness)
			}
			return nil
		},
	}
	cmd.Flags().BoolVar(&jsonOut, "json", false, "Output as JSON")
	return cmd
}

func statusCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "Check if OpenRazer daemon is available (outputs JSON)",
		RunE: func(cmd *cobra.Command, args []string) error {
			c, err := razer.NewClient()
			if err != nil {
				fmt.Println(`{"available":false,"version":"","devices":0}`)
				return nil
			}
			defer c.Close()

			version, _ := c.DaemonVersion()
			serials, _ := c.DeviceSerials()
			fmt.Printf(`{"available":true,"version":%q,"devices":%d}`+"\n",
				version, len(serials))
			return nil
		},
	}
}

func infoCmd() *cobra.Command {
	var device string
	cmd := &cobra.Command{
		Use:   "info",
		Short: "Show detailed device info",
		RunE: func(cmd *cobra.Command, args []string) error {
			return withClient(func(c *razer.Client) error {
				d, err := resolveDevice(c, device)
				if err != nil {
					return err
				}
				info := d.Info()
				return json.NewEncoder(os.Stdout).Encode(info)
			})
		},
	}
	cmd.Flags().StringVarP(&device, "device", "d", "", "Device selector (index, serial, or name)")
	return cmd
}

func brightnessCmd() *cobra.Command {
	var device string
	cmd := &cobra.Command{
		Use:   "brightness [level]",
		Short: "Get or set brightness (0-100)",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return withClient(func(c *razer.Client) error {
				d, err := resolveDevice(c, device)
				if err != nil {
					return err
				}

				if len(args) == 0 {
					b, err := d.Brightness()
					if err != nil {
						return err
					}
					fmt.Printf("%.0f\n", b)
					return nil
				}

				level, err := strconv.ParseFloat(args[0], 64)
				if err != nil || level < 0 || level > 100 {
					return fmt.Errorf("brightness must be 0-100")
				}
				return d.SetBrightness(level)
			})
		},
	}
	cmd.Flags().StringVarP(&device, "device", "d", "", "Device selector")
	return cmd
}

func effectCmd() *cobra.Command {
	var device string

	cmd := &cobra.Command{
		Use:   "effect",
		Short: "Set lighting effect",
	}
	cmd.PersistentFlags().StringVarP(&device, "device", "d", "", "Device selector")

	// static
	staticCmd := &cobra.Command{
		Use:   "static <hex-color>",
		Short: "Set static color (e.g. ff0000)",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			r, g, b, err := parseHexColor(args[0])
			if err != nil {
				return err
			}
			return withClient(func(c *razer.Client) error {
				d, err := resolveDevice(c, device)
				if err != nil {
					return err
				}
				return d.SetStatic(r, g, b)
			})
		},
	}

	// breathing
	breathCmd := &cobra.Command{
		Use:   "breath [hex-color] [hex-color2]",
		Short: "Set breathing effect (0 colors=random, 1=single, 2=dual)",
		Args:  cobra.MaximumNArgs(2),
		RunE: func(cmd *cobra.Command, args []string) error {
			return withClient(func(c *razer.Client) error {
				d, err := resolveDevice(c, device)
				if err != nil {
					return err
				}
				switch len(args) {
				case 0:
					return d.SetBreathRandom()
				case 1:
					r, g, b, err := parseHexColor(args[0])
					if err != nil {
						return err
					}
					return d.SetBreathSingle(r, g, b)
				case 2:
					r1, g1, b1, err := parseHexColor(args[0])
					if err != nil {
						return err
					}
					r2, g2, b2, err := parseHexColor(args[1])
					if err != nil {
						return err
					}
					return d.SetBreathDual(r1, g1, b1, r2, g2, b2)
				}
				return nil
			})
		},
	}

	// wave
	waveCmd := &cobra.Command{
		Use:   "wave [left|right]",
		Short: "Set wave effect (default: left)",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			dir := 1
			if len(args) > 0 && strings.ToLower(args[0]) == "right" {
				dir = 2
			}
			return withClient(func(c *razer.Client) error {
				d, err := resolveDevice(c, device)
				if err != nil {
					return err
				}
				return d.SetWave(dir)
			})
		},
	}

	// spectrum
	spectrumCmd := &cobra.Command{
		Use:   "spectrum",
		Short: "Set spectrum (rainbow cycle) effect",
		RunE: func(cmd *cobra.Command, args []string) error {
			return withClient(func(c *razer.Client) error {
				d, err := resolveDevice(c, device)
				if err != nil {
					return err
				}
				return d.SetSpectrum()
			})
		},
	}

	// reactive
	var speed byte
	reactiveCmd := &cobra.Command{
		Use:   "reactive <hex-color>",
		Short: "Set reactive effect (keys light up on press)",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			r, g, b, err := parseHexColor(args[0])
			if err != nil {
				return err
			}
			if speed < 1 || speed > 4 {
				return fmt.Errorf("speed must be 1-4")
			}
			return withClient(func(c *razer.Client) error {
				d, err := resolveDevice(c, device)
				if err != nil {
					return err
				}
				return d.SetReactive(r, g, b, speed)
			})
		},
	}
	reactiveCmd.Flags().Uint8VarP(&speed, "speed", "s", 2, "Reaction speed 1-4 (slow to fast)")

	// starlight
	starlightCmd := &cobra.Command{
		Use:   "starlight [hex-color]",
		Short: "Set starlight effect (0 colors=random, 1=single color)",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return withClient(func(c *razer.Client) error {
				d, err := resolveDevice(c, device)
				if err != nil {
					return err
				}
				if len(args) == 0 {
					return d.SetStarlightRandom(speed)
				}
				r, g, b, err := parseHexColor(args[0])
				if err != nil {
					return err
				}
				return d.SetStarlightSingle(r, g, b, speed)
			})
		},
	}
	starlightCmd.Flags().Uint8VarP(&speed, "speed", "s", 2, "Starlight speed 1-3")

	// none (off)
	noneCmd := &cobra.Command{
		Use:   "none",
		Short: "Turn off lighting",
		RunE: func(cmd *cobra.Command, args []string) error {
			return withClient(func(c *razer.Client) error {
				d, err := resolveDevice(c, device)
				if err != nil {
					return err
				}
				return d.SetNone()
			})
		},
	}

	cmd.AddCommand(staticCmd, breathCmd, waveCmd, spectrumCmd, reactiveCmd, starlightCmd, noneCmd)
	return cmd
}

func dpiCmd() *cobra.Command {
	var device string
	cmd := &cobra.Command{
		Use:   "dpi [value]",
		Short: "Get or set DPI (sets both axes)",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return withClient(func(c *razer.Client) error {
				d, err := resolveDevice(c, device)
				if err != nil {
					return err
				}
				if len(args) == 0 {
					dpi, err := d.DPI()
					if err != nil {
						return err
					}
					if len(dpi) >= 2 {
						fmt.Printf("%d,%d\n", dpi[0], dpi[1])
					}
					return nil
				}
				val, err := strconv.ParseUint(args[0], 10, 16)
				if err != nil {
					return fmt.Errorf("invalid DPI value: %w", err)
				}
				return d.SetDPI(uint16(val), uint16(val))
			})
		},
	}
	cmd.Flags().StringVarP(&device, "device", "d", "", "Device selector")
	return cmd
}

// parseHexColor parses a hex color string (with or without #) into RGB bytes.
func parseHexColor(s string) (byte, byte, byte, error) {
	s = strings.TrimPrefix(s, "#")
	if len(s) != 6 {
		return 0, 0, 0, fmt.Errorf("invalid hex color %q (expected 6 hex digits)", s)
	}
	val, err := strconv.ParseUint(s, 16, 32)
	if err != nil {
		return 0, 0, 0, fmt.Errorf("invalid hex color %q: %w", s, err)
	}
	return byte(val >> 16), byte(val >> 8), byte(val), nil
}
