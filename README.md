# mandel_basys3
## A fast (1.5 GigaIters/s) Mandelbrot generator for the Digilent Basys3 FPGA trainer board.

![screenshots](media/mandel_b3-20221231-small.jpg)

# REQUIREMENTS

- Digilent Basys3 FPGA trainer board.
- VGA display (or HDMI via a cheap VGA to HDMI converter).

# CONTROLS

Use the "cross" buttons (U,D,L,R,C) on the Basys3 board.
- Up, Down, Left, Right: Move around in complex plane.

Keep the C (Center) button pressed for these actions:
- Center + Up: Zoom in 2x.
- Center + Down: Zoom out 2x.
- Center + Left (S): Increase iterations.
- Center + Right (D): Decrese iterations.

4-Digit LED display:
- If Center button is NOT pressed: Display current calculation line in hex [0x00..0xF0].
- If Center button is pressed: Display current max_iters per pixel in hex [0x10..0xFFF].
NOTE: While the Center button is pressed. 

# SUPPORTED RESOLUTIONS
- 320x240, RGB 4:4:4.

NOTE: The limited amount of BRAM in the Basys3 (XC7A35T) only allows for a 320x240 (QVGA) framebuffer. We upscale it to output 640x480 VGA @ 60 Hz.
NOTE: The coloring algorithm maps iterations to a palette of 256 colors. However, the framebuffer is RGB 4:4:4, so an enhanced version with a custom coloring algorithm can be easily implemented.

# ALGORITHM

### Mandelbrot calculation
This is a brute force algorithm using Q3.22 fixed-point precision.
We don't need heuristic optimizations, as we can reach interactive rates also at the maximum 4095 iters/pixel.
The hard work is done by the 15 Mandelbrot calculation engines working in parallel at 100 MHz.
Each engine uses 6 DSP48E1 resources on the FPGA to calculate 1 Mandelbrot iteration per clock cycle. Aggregate computational power is 1.5 GigaIters/sec.

### Note about fixed-point precision

There are two different fixed-point notations using "Q" numbers. TI and ARM. I am using ARM notation. More info here:  
https://en.wikipedia.org/wiki/Q_(number_format)  

The current implementation uses Q3.22 (25 bits total).  
The Mandelbrot set is contained in a circle with radius 2. However, during calculation, numbers greater than 2 are encountered, depending on the point being calculated.  
Here is the maximum magnitude reached for each point during the calculation:  

![screenshots](media/max_values.jpg)

Q3.22 is the best compromise between max-zoom and speed for the Artix7 FPGA.

# LICENSE

Creative Commons, CC BY

https://creativecommons.org/licenses/by/4.0/deed.en

Please add a link to this github project.
