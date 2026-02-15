# Scott Adams Grand Adventures

Interpreter for Scott Adams games

## Files

- [saga.pl](saga.pl)\
Interpreter written in vanilla Perl.
Note output uses ANSI terminal escape sequences.\
\
Usage: ./saga.pl [-d] gamefile [savefile]\
\
      -d - Output a decompiled representation of the gamefile and exit\
gamefile - The adventure game data file\
savefile - Loads a saved game from the file, typically created via "SAVE GAME"

- [tictactoe.dat](tictactoe.dat)\
A two player tic-tac-toe game in Adventure game format.

- [tictactoe_vs_computer.dat](tictactoe_vs_computer.dat)\
A one player tic-tac-toe game in Adventure game format vs the "computer".
The computer just moves randomly in this version.

- [Maps](maps)\
Maps of adventures.  Warning: spoilers

## See Also

- [https://msadams.com](https://msadams.com)\
Scott Adams Grand Adventures home page

- [https://andwj.gitlab.io/scott_specs/](https://andwj.gitlab.io/scott_specs/)\
The Unofficial SAGA Specification v0.9

- [https://www.trs-80.com/sub-details-scott-adams.htm](https://www.trs-80.com/sub-details-scott-adams.htm)\
TRS-80 Software: Scott Adams Adventures
