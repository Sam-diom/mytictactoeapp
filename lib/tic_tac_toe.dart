import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mytictactoeapp/enums.dart';

import 'custom_dialog.dart';

class TicTacToeScreen extends StatefulWidget {
  final Socket socket;
  final bool isServer;

  const TicTacToeScreen({
    Key? key,
    required this.socket,
    required this.isServer,
  }) : super(key: key);

  @override
  State<TicTacToeScreen> createState() => _TicTacToeScreenState();
}

typedef CanUnlock = bool Function();

class _TicTacToeScreenState extends State<TicTacToeScreen> {
  bool _waitingForAnotherUser = false;
  String? _whoAmI;
  late List<List<String>> _board;
  String _currentPlayer = "X";
  bool _gameOver = false;
  Timer? _handshakeLock;
  CanUnlock _canUnlock = () => false;
  bool _isTie = false;

  @override
  void initState() {
    super.initState();
    _multiplayerSetup();
    startNewGame(restartGame: null);
  }

  @override
  void dispose() {
    widget.socket.destroy();
    _handshakeLock?.cancel();
    super.dispose();
  }

  void _multiplayerSetup() async {
    widget.socket.listen((event) {
      log("Event $event");
      if (event is List<dynamic>) {
        if (event[2] == Handshake.sendToOther.index) {
          makeMove(event[0], event[1], Handshake.otherPersonReceived);
        } else if (event[2] == Handshake.handshakeSuccess.index) {
          makeMove(event[0], event[1], Handshake.handshakeSuccess);
        }
      } else if (event is List<int> && event.length == 1) {
        startNewGame(restartGame: event[0]);
      }
    }).onDone(() {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("l'autre joueur a abandonné")));
      Navigator.pop(context);
    });
  }

  void startNewGame({required int? restartGame}) async {
    _clearBoard();
    _isTie = false;
    if (restartGame == null) {
      _whoAmI = widget.isServer ? 'X' : 'O';
    } else if (restartGame == RestartGameRequest.send.index) {
      log("Envoi d'une demande à l'autre joueur pour commencer la partie");
      _waitingForAnotherUser = true;
      widget.socket.add([RestartGameRequest.received.index]);
      setState(() {});
    } else if (restartGame == RestartGameRequest.received.index) {
      _performRestartReceivedAction();
    } else if (restartGame == RestartGameRequest.bothConfirmed.index) {
      _waitingForAnotherUser = false;
      log("L'autre joueur a accepté votre demande, vous pouvez maintenant commencer à jouer");
      _startingTheGame();
    } else if (restartGame == RestartGameRequest.rejected.index) {
      _waitingForAnotherUser = false;
      log("Another player rejected you");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Another player rejected you",
          ),
        ),
      );
      setState(() {});
    }
  }

  void _performRestartReceivedAction() async {
    log("Restart game request received");
    if (!_gameOver) {
      _gameStartConfirmation();
      return;
    }
    final value = await showDialog(
      context: context,
      builder: (context) {
        return const CustomDialog(
          title: "Play Again",
          content: "Do you want to play again!",
          no: "I need rest.",
        );
      },
    );
    if (value == true) {
      _gameStartConfirmation();
    } else {
      widget.socket.add([RestartGameRequest.rejected.index]);
    }
  }

  void _gameStartConfirmation() {
    widget.socket.add([RestartGameRequest.bothConfirmed.index]);
    _startingTheGame();
  }

  void _startingTheGame() {
    if (_gameOver) {
      _whoAmI = switchZeroCross(_whoAmI ?? 'X');
    }
    _currentPlayer = 'X';
    _clearBoard();
    _gameOver = false;
    setState(() {});
  }

  void _clearBoard() {
    _board = List<List<String>>.generate(3, (_) => List<String>.filled(3, ''));
  }

  void makeMove(int row, int col, Handshake handshake) {
    if ((_board[row][col] != '' || _gameOver)) {
      _cancelTimer();
      return;
    }
    log("Make Move. Row: $row Column:$col $handshake");
    if (handshake == Handshake.sendToOther) {
      _canUnlock = () => _board[row][col].isNotEmpty;
      _handshakeLock = Timer(const Duration(milliseconds: 250), () {
        if (_canUnlock()) {
          _cancelTimer();
        } else {
          log("Packet get lost, resending");
          makeMove(row, col, Handshake.sendToOther);
        }
      });
      widget.socket.add([row, col, handshake.index]);
    } else {
      if (handshake == Handshake.otherPersonReceived) {
        widget.socket.add([row, col, Handshake.handshakeSuccess.index]);
      }
      setState(() {
        _board[row][col] = _currentPlayer;
        checkWinner(row, col);
        _currentPlayer = switchZeroCross(_currentPlayer);
        _cancelTimer();
      });
    }
  }

  void _cancelTimer() {
    _handshakeLock?.cancel();
    _handshakeLock = null;
  }

  String switchZeroCross(String value) {
    return value == 'X' ? 'O' : 'X';
  }

  void checkWinner(int row, int col) {
    // Check for a win
    if (!_gameOver) {
      // Check row
      if (_board[row][0] == _board[row][1] &&
          _board[row][1] == _board[row][2] &&
          _board[row][0] != '') {
        _gameOver = true;
      }

      // Check column
      if (_board[0][col] == _board[1][col] &&
          _board[1][col] == _board[2][col] &&
          _board[0][col] != '') {
        _gameOver = true;
      }

      // Check diagonal
      if (_board[0][0] == _board[1][1] &&
          _board[1][1] == _board[2][2] &&
          _board[0][0] != '') {
        _gameOver = true;
      }
      if (_board[0][2] == _board[1][1] &&
          _board[1][1] == _board[2][0] &&
          _board[0][2] != '') {
        _gameOver = true;
      }

      // Check for a tie
      if (!_board.any((row) => row.any((cell) => cell == '')) && !_gameOver) {
        _gameOver = true;
        _isTie = true;
      }
    }

    if (_gameOver) {
      if (!_isTie) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "${_currentPlayer == _whoAmI ? "You" : "Opponent"} won the game!")));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("The game ended in a tie!")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final value = await showDialog(
            context: context,
            builder: (context) {
              return const CustomDialog(
                title: "Give Up!",
                content:
                    "Are you okay if your friends mock you for a guy who easily give up?",
              );
            });
        if (value == true) {
          if (!mounted) return Future.value(false);
          Navigator.pop(context);
        }
        return Future.value(false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tic Tac Toe'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_gameOver) ...[
                Text(
                  'You are $_whoAmI \n(${_whoAmI == _currentPlayer ? "Your" : "Opponent"}\'s Turn)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxHeight: 400, maxWidth: 400),
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 1.0,
                        crossAxisSpacing: 4.0,
                        mainAxisSpacing: 4.0,
                      ),
                      itemCount: 9,
                      itemBuilder: (context, index) {
                        final row = index ~/ 3;
                        final col = index % 3;
                        return GestureDetector(
                          onTap: () {
                            if (_currentPlayer != _whoAmI ||
                                _handshakeLock != null ||
                                _gameOver) return;
                            makeMove(row, col, Handshake.sendToOther);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(255, 183, 233, 185),
                              border: Border.all(color: Colors.black),
                            ),
                            child: Container(
                              color: _board[row][col] == 'X'
                                  ? Colors.amberAccent
                                  : (_board[row][col] == "O")
                                      ? Colors.redAccent
                                      : const Color.fromARGB(
                                          255, 183, 233, 185),
                              child: Center(
                                child: Text(
                                  _board[row][col],
                                  style: const TextStyle(fontSize: 40),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ] else ...[
                const Text(
                  "Game Over!",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 30,
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _waitingForAnotherUser
                      ? null
                      : () {
                          startNewGame(
                              restartGame: RestartGameRequest.send.index);
                        },
                  child: Text(_waitingForAnotherUser
                      ? "Waiting For Another Player"
                      : 'Start New Game'),
                ),
                const SizedBox(
                  height: 20,
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}
