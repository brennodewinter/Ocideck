// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

extension _PresenterKeys on _FullscreenPresenterState {
  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // Cmd+W / Ctrl+W sluit de presentatie, net als het sluiten van een venster
    // elders in het systeem — werkt in elke modus, ongeacht overlays.
    final hw = HardwareKeyboard.instance;
    if ((hw.isMetaPressed || hw.isControlPressed) &&
        key == LogicalKeyboardKey.keyW) {
      _exit();
      return KeyEventResult.handled;
    }

    // Sneltoets-overzicht vangt alles: sluiten met ? / H / Esc.
    if (_helpOpen) {
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.keyH ||
          key == LogicalKeyboardKey.question) {
        _rebuild(() => _helpOpen = false);
      }
      return KeyEventResult.handled;
    }

    // Doeltijd-invoer vangt cijfers/Enter/Esc tot de invoer klaar is.
    if (_targetInput) return _handleTargetKey(key);

    // Gebruikersnotities: sluiten/togglen en bladeren met PgUp/PgDn; overige
    // toetsen (inclusief pijltjes, die de cursor besturen) naar het veld.
    if (_userNotesMode) {
      final keys = HardwareKeyboard.instance;
      if (key == LogicalKeyboardKey.escape) {
        _closeUserNotesMode();
        return KeyEventResult.handled;
      }
      if ((keys.isControlPressed || keys.isMetaPressed) &&
          key == LogicalKeyboardKey.keyN) {
        _toggleUserNotesMode();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.pageDown) {
        _next(allowInUserNotes: true);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.pageUp) {
        _prev(allowInUserNotes: true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Terwijl het raster open is, sturen de pijltjes een aparte cursor aan.
    if (_gridOpen) return _handleGridKey(key);

    // Tabelbewerking: navigatie-toetsen voor celkeuze; tekstinvoer blijft intact.
    if (_tableEditMode) return _handleTableEditKey(key);

    // Cijfers verzamelen om naar een slidenummer te springen.
    final digit = _digits[key];
    if (digit != null) {
      _appendDigit(digit);
      return KeyEventResult.handled;
    }

    final keys = HardwareKeyboard.instance;
    if ((keys.isControlPressed || keys.isMetaPressed) &&
        key == LogicalKeyboardKey.keyN) {
      _toggleUserNotesMode();
      return KeyEventResult.handled;
    }

    return _handleNavKey(key);
  }

  KeyEventResult _handleNavKey(LogicalKeyboardKey key) {
    final last = widget.slides.length - 1;
    switch (key) {
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        // Met een getypt nummer: springen; anders gewoon door.
        if (_typed.isNotEmpty) {
          _commitTyped();
        } else {
          _next();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.backspace:
        if (_typed.isNotEmpty) {
          _rebuild(() => _typed = _typed.substring(0, _typed.length - 1));
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyH:
      case LogicalKeyboardKey.question:
        _toggleHelp();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.pageDown:
        _next();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.pageUp:
        _prev();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _goTo(0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        _goTo(last);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyP:
        _togglePresenterView();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyR:
        _resetTimer();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyK:
        _beginTargetInput();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyB:
        _toggleBlank(_Blank.black);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyW:
        _toggleBlank(_Blank.white);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyG:
        _toggleGrid();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyA:
        _toggleAutoPlay();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyL:
        _toggleLoop();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyM:
        _toggleMediaAdvance();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyS:
        _cycleDisplay();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyD:
        _setTool(InkTool.pen);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyT:
        _setTool(InkTool.highlighter);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyE:
        if (HardwareKeyboard.instance.isShiftPressed) {
          _setTool(InkTool.eraser);
        } else if (_currentSlideTableEditable) {
          _toggleTableEditMode();
        } else {
          _setTool(InkTool.eraser);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyX:
        _setTool(InkTool.laser);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyC:
        _clearCurrentInk();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        // Gelaagd: gebruikersnotities, tabelbewerking, gereedschap, getypt
        // nummer, blanco, afsluiten.
        if (_userNotesMode) {
          _closeUserNotesMode();
        } else if (_tableEditMode) {
          _exitTableEditMode();
        } else if (_tool != null) {
          _rebuild(() => _tool = null);
          _onLaserMove(null);
        } else if (_typed.isNotEmpty) {
          _clearTyped();
        } else if (_blank != _Blank.none) {
          _rebuild(() => _blank = _Blank.none);
        } else {
          _exit();
        }
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  /// Toetsen terwijl de doeltijd wordt ingevoerd (MMSS). Alles wordt
  /// opgeslokt zodat losse cijfers niet als slidesprong gelden.
  KeyEventResult _handleTargetKey(LogicalKeyboardKey key) {
    final digit = _digits[key];
    if (digit != null) {
      _rebuild(() {
        _targetTyped += digit;
        if (_targetTyped.length > 4) {
          _targetTyped = _targetTyped.substring(_targetTyped.length - 4);
        }
      });
      return KeyEventResult.handled;
    }
    switch (key) {
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.keyK:
        _commitTarget();
      case LogicalKeyboardKey.backspace:
        if (_targetTyped.isNotEmpty) {
          _rebuild(
            () => _targetTyped = _targetTyped.substring(
              0,
              _targetTyped.length - 1,
            ),
          );
        }
      case LogicalKeyboardKey.escape:
        _cancelTargetInput();
      default:
        break;
    }
    return KeyEventResult.handled;
  }

  /// Toetsen terwijl het rasteroverzicht open is.
  KeyEventResult _handleGridKey(LogicalKeyboardKey key) {
    final last = widget.slides.length - 1;
    switch (key) {
      case LogicalKeyboardKey.arrowRight:
        _moveGridCursor(1);
      case LogicalKeyboardKey.arrowLeft:
        _moveGridCursor(-1);
      case LogicalKeyboardKey.arrowDown:
        _moveGridCursor(_gridCols);
      case LogicalKeyboardKey.arrowUp:
        _moveGridCursor(-_gridCols);
      case LogicalKeyboardKey.home:
        _setGridCursor(0);
      case LogicalKeyboardKey.end:
        _setGridCursor(last);
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.space:
        _jumpTo(_gridCursor);
      case LogicalKeyboardKey.keyG:
      case LogicalKeyboardKey.escape:
        _rebuild(() => _gridOpen = false);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }
}
