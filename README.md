# Rotatron [WIP]

User space daemon to handle screen rotation on X11 based on accelerometer device.

The development was carried out with the [Samsung Galaxy Book 4 360](https://www.samsung.com/br/computers/samsung-book/galaxy-book4-360-15-6-inch-core-5-16gb-512gb-np750qgk-kg2br/) in mind.

## My use case

On a setup with i3 window manager there are a button in the polybar wich when holded (or mouse 3) will toggle modes between automatic and manual modes and when tapped (mouse 1) will set the orientation to the current accelerometer indicated position changing to manual mode.

The appearance of the button inverts the background and foreground colors to indicate the mode (manual or automatic) the daemon is operating.

> [WIP] The program contains hardcoded shell commands to correctly update my graphical elements such as wallpaper on feh and polybar. Its planned to have flags to specify those actions through the cli.

## Architecture

The software have two pieces: a `daemon` and `clients`. The `daemon` is meant to run in background as a system service to which the `clients` connects via unix socket to send commands and query state. Both pieces lives under the same binary and are differentiated by the commands passed to it.

Operational wise, there are two modes of operation: `manual` and `automatic`. When in `automatic` mode the application will constantly poll the sensor data and automaticaly adjust the orientation. On `manual` mode the application only changes the orientation on client `set` command.

Right now the code is able to automatically find the accelerometer device and the display is known by the xrandr extension, but the findig of the touchscreen device is still a [TODO](##TODO).

## Usage

```sh
rotatron <command> [args]...

```

### Commands
- `daemon`: starts the daemon service. If the unix socket already exists, exits with code 1;
    ```sh
    rotatron daemon
    ```

- `interactive`: starts a client interactive session in wich the stdio are connected to the unix socket to send direct [messages](###Messages);
    ```sh
    rotatron interactive
    ```

- `set`: one shot client command with optional direction parameter to set the orientation. If no directio is passed, the accelerometer will be used to determine the orientation.
    ```sh
    rotatron set [up|down|left|right]
    ```

- `toggle`: one shot client command that toggles between automatic and manual modes.
    ```sh
    rotatron toggle
    ```

- `mode`: one shot client command used to query the mode in wich the daemon is operation. It is expected to print the literal message `AUTOMATIC` or `MANUAL` on stdout.
    ```sh
    rotatron mode
    ```

### Messages

The underlying comunication mechanism uses messages exchanged bidirectionaly between daemon and client through an unix socket. The messages are aways initiated from the client and from each send from the client to the server there are a response from the server to the client. The messages and its returns are:

- `quit` -> `OK`: closes connection;
- `manual` -> `OK`: changes to manual mode;
- `automatic` -> `OK`: changes to automatic mode;
- `toggle` -> `OK`: toggles between automatic and manual mode;
- `set [up|down|left|right]` -> `OK`: changes the mode to manual and sets direction to the giver one or else to the one given by the accelerometer device;
- `stop` -> `OK`: stops daemon process;
- `mode [automatic|manual]` -> `AUTOMATIC` | `MANUAL`: If argument is passed, change the operation mode of the daemon. If no arg, queries the current mode of operation.

Any other string passed will be ignored. The `interactive` command is the best way to explore those valid messages.

## Known issues

- The X11 display server have serious problems with screen tearing;
- Because X11 and Xrandr, the transition from one orientation to another is a drag:
    - Can take some seconds
    - Screens goes black
- On i3wm, floating windows goes nuts, sometimes desapearing from positions not visible;
- All graphicall elements like bars and wallpapers needs to be manualy reloaded before change in orientation, to recalculate sizes and placement.

I hope all those issues can be solved on a Wayland environment, once the support for it is added.

## TODO

- [ ] automatically find the touch screen device on xinput
- [ ] wayland support
- [ ] remove hardcoded shell commands to reload graphical elements and implementation of flags to pass those commands through the cli
- [ ] add screenshots and GIFS to this readme
- [ ] add completions
- [ ] create man page
- [x] automatic release through actions
- [ ] fix signal handling (CTRL-C not working)

