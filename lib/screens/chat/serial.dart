import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:xc/components/chat_app_bar.dart';
import 'package:xc/components/chat_messages.dart';
import 'package:xc/components/chat_clear_dialog.dart';
import 'package:xc/components/chat_text_field.dart';
import 'package:xc/components/scroll_follow.dart';
import 'package:xc/controllers/comm_serial.dart';
import 'package:xc/cubit/chat_cubit.dart';
import 'package:xc/cubit/comm_cubit.dart';
import 'package:xc/cubit/serial_cubit.dart';
import 'package:xc/static/comm_message.dart';
import 'package:xc/static/comm_status.dart';

class SerialChat extends StatefulWidget {
  const SerialChat({super.key});

  @override
  State<SerialChat> createState() => _SerialChatState();
}

class _SerialChatState extends State<SerialChat> {
  final TextEditingController textEditingController = TextEditingController();
  final FocusNode textEditingFocusNode = FocusNode();
  final ScrollController _listScrollController = ScrollController();
  CommSerial comm = CommSerial();

  @override
  void initState() {
    super.initState();
    textEditingFocusNode.requestFocus();
    _initComm();
  }

  @override
  void dispose() {
    comm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serverName = comm.port.name ?? AppLocalizations.of(context)!.unknown;

    return Scaffold(
      appBar: ChatAppBar(status: comm.status, clearDialog: _clearDialog),
      body: Column(
        children: <Widget>[
          ChatMessages(scrollController: _listScrollController),
          ChatUserInput(
            onPressed: _send,
            onSubmitted: (p0) => _send(),
            serverName: serverName,
            status: comm.status,
            focusNode: textEditingFocusNode,
            textEditingController: textEditingController,
          ),
        ],
      ),
    );
  }

  _initComm() async {
    final device = context.read<SerialCubit>();
    final preferences = context.read<CommCubit>();

    await comm.init(device, preferences);

    setState(() {});

    if (comm.status == CommStatus.connected) {
      Stream<String> upcommingData = comm.reader.stream.map((event) {
        return String.fromCharCodes(event);
      });

      upcommingData.listen((event) {
        _receive(comm.stringToUinut8List(event));
      });

      if (mounted) {
        setState(() {});
      }
    }

    scrollFollow(_listScrollController);
  }

  void _send() {
    final text = textEditingController.text.trim();

    debugPrint(text);

    textEditingFocusNode.requestFocus();

    if (text.isEmpty) {
      return;
    }

    final chat = context.read<ChatCubit>();

    try {
      comm.send(text);
      chat.add(Message(comm.clientID, text));

      setState(() {
        textEditingController.clear();
      });

      scrollFollow(_listScrollController);
    } catch (error) {
      debugPrint(error.toString());
      setState(() {});
    }
  }

  void _receive(Uint8List event) {
    // Allocate buffer for parsed data
    int backspacesCounter = 0;
    for (var byte in event) {
      if (byte == 8 || byte == 127) {
        backspacesCounter++;
      }
    }
    Uint8List buffer = Uint8List(event.length - backspacesCounter);
    int bufferIndex = buffer.length;

    // Apply backspace control character
    backspacesCounter = 0;
    for (int i = event.length - 1; i >= 0; i--) {
      if (event[i] == 8 || event[i] == 127) {
        backspacesCounter++;
      } else {
        if (backspacesCounter > 0) {
          backspacesCounter--;
        } else {
          buffer[--bufferIndex] = event[i];
        }
      }
    }

    final chat = context.read<ChatCubit>();
    String dataString = String.fromCharCodes(buffer);
    int index = buffer.indexOf(10);
    if (~index != 0) {
      setState(() {
        chat.add(
          Message(
            1,
            backspacesCounter > 0
                ? comm.messageBuffer
                    .substring(0, comm.messageBuffer.length - backspacesCounter)
                : comm.messageBuffer + dataString.substring(0, index),
          ),
        );
        comm.messageBuffer = dataString.substring(index);
      });
      scrollFollow(_listScrollController);
    } else {
      comm.messageBuffer = (backspacesCounter > 0
          ? comm.messageBuffer
              .substring(0, comm.messageBuffer.length - backspacesCounter)
          : comm.messageBuffer + dataString);
    }
  }

  Future<void> _clearDialog() async {
    await clearChatDialog(context);
    setState(() {});
    textEditingFocusNode.requestFocus();
  }
}
