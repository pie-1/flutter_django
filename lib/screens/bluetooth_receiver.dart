// receiver_bluetooth_server_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/transactions_queue.dart';

class ReceiverBluetoothServerScreen extends StatefulWidget {
  const ReceiverBluetoothServerScreen({super.key});

  @override
  State<ReceiverBluetoothServerScreen> createState() => _ReceiverBluetoothServerScreenState();
}

class _ReceiverBluetoothServerScreenState extends State<ReceiverBluetoothServerScreen> {
  final BLEService _bleService = BLEService();
  String _connectionStatus = 'Initializing...';
  List<Map<String, dynamic>> _pendingRequests = [];
  StreamSubscription? _messageSubscription;
  StreamSubscription? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _initializeBluetooth();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _statusSubscription?.cancel();
    _bleService.disconnect();
    super.dispose();
  }

  Future<void> _initializeBluetooth() async {
    // Check if Bluetooth is available
    final isAvailable = await _bleService.isBluetoothAvailable();
    if (!isAvailable) {
      setState(() {
        _connectionStatus = 'Bluetooth not available. Please enable Bluetooth.';
      });
      return;
    }

    // Listen to connection status
    _statusSubscription = _bleService.connectionStatusStream.listen((status) {
      setState(() {
        _connectionStatus = status;
      });
    });

    // Listen to incoming messages
    _messageSubscription = _bleService.messageStream.listen((message) {
      _handleIncomingMessage(message);
    });

    // Start scanning to make device discoverable
    setState(() {
      _connectionStatus = 'Ready to receive payments. Make sure your device is discoverable.';
    });
  }

  void _handleIncomingMessage(Map<String, dynamic> message) {
    if (message['type'] == 'payment_request') {
      setState(() {
        _pendingRequests.add(message);
      });
      _showPaymentRequestDialog(message);
    }
  }

  Future<void> _showPaymentRequestDialog(Map<String, dynamic> request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.payment, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Payment Request'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'From: ${request['sender_name']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Phone: ${request['sender_phone']}'),
            const SizedBox(height: 8),
            Text(
              'Amount: ₹${request['amount']}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            if (request['description']?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text('Description: ${request['description']}'),
            ],
            const SizedBox(height: 16),
            const Text(
              'Do you want to accept this payment?',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Reject'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    // Send response
    final transactionId = request['transaction_id'];
    await _bleService.sendPaymentResponse(
      transactionId: transactionId,
      accepted: confirmed ?? false,
      reason: confirmed == false ? 'Payment rejected by receiver' : null,
    );

    // If accepted, save to transaction queue
    if (confirmed == true) {
      await TransactionQueue.queue({
        'method': 'P2P-BT',
        'name': request['sender_name'],
        'phone': request['sender_phone'],
        'amount': request['amount'],
        'description': request['description'] ?? '',
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'completed',
        'transaction_id': transactionId,
        'type': 'received',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment of ₹${request['amount']} accepted and recorded'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }

    // Remove from pending requests
    setState(() {
      _pendingRequests.removeWhere((req) => req['transaction_id'] == transactionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Receive Payment'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Status Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Icon(
                      Icons.bluetooth_searching,
                      size: 48,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Bluetooth Payment Receiver',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _connectionStatus,
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Instructions
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'How to receive payments:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildInstructionStep('1', 'Keep this screen open'),
                    _buildInstructionStep('2', 'Make sure Bluetooth is enabled'),
                    _buildInstructionStep('3', 'Ask sender to scan for your device'),
                    _buildInstructionStep('4', 'Accept or reject payment requests'),
                  ],
                ),
              ),
            ),
            
            const Spacer(),
            
            // Pending requests indicator
            if (_pendingRequests.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.pending_actions, color: colorScheme.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Text(
                      '${_pendingRequests.length} pending request(s)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
