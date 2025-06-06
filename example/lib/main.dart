/*
 * (c) Copyright IBM Corp. 2021
 * (c) Copyright Instana Inc. and contributors 2021
 */

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:instana_agent/instana_agent.dart';

import 'http_client.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<Album> futureAlbum;

  @override
  void initState() {
    super.initState();

    /// Initializes Instana. Must be run only once as soon as possible in the app's lifecycle
    setupInstana();

    /// optional
    futureAlbum = fetchAlbum();
  }

  void setupInstana() async {
    var options = SetupOptions();
    options.collectionEnabled = false;
    // options.slowSendInterval = 60.0; // enable slow send mode on beacon send failure, send interval is 60 seconds
    // options.usiRefreshTimeIntervalInHrs = 24.0; // refresh user session id every 24 hours

    // Each string in queryTrackedDomainList is treated as a regular expression.
    // options.queryTrackedDomainList = ['https://jsonplaceholder\\.typicode\\.com', 'https://www\\.ibm\\.com*'];
    // options.rateLimits = RateLimits.MID_LIMITS;
    bool ret = await InstanaAgent.setup(key: 'key', reportingUrl: 'URL', options: options);
    if (!ret) {
      // Error handling here
      if (kDebugMode) {
        print("InstanaAgent setup failed");
      }
    }

    setUserIdentifiers();

    InstanaAgent.setCollectionEnabled(true);

    /// optional
    setView();

    InstanaAgent.setCaptureHeaders(regex: [
      'x-ratelimit-limit',
      'x-ratelimit-remaining',
      'x-ratelimit-reset'
    ]);

    InstanaAgent.redactHTTPQuery(regex: ['uid', 'user']);

    /// optional
    reportCustomEvents();
  }

  /// Set user identifiers
  ///
  /// These will be attached to all subsequent beacons
  setUserIdentifiers() {
    InstanaAgent.setUserID('1234567890');
    InstanaAgent.setUserName('Boty McBotFace');
    InstanaAgent.setUserEmail('boty@mcbot.com');
  }

  /// Setting a view allows for easier logical segmentation of beacons in the timeline shown in the Instana Dashboard's Session
  setView() {
    InstanaAgent.setView('Home');
  }

  /// At any time, Metadata can be added to Instana beacons and events can be generated
  Future<void> reportCustomEvents() async {
    InstanaAgent.setMeta(key: 'exampleGlobalKey', value: 'exampleGlobalValue');

    await InstanaAgent.reportEvent(name: 'simpleCustomEvent');
    await InstanaAgent.reportEvent(name: 'customEventWithMetric',
        options: EventOptions()
          ..customMetric = 12345.678);
    await InstanaAgent.reportEvent(
        name: 'complexCustomEvent',
        options: EventOptions()
          ..viewName = 'customViewName'
          ..startTime = DateTime.now().millisecondsSinceEpoch
          ..duration = 2 * 1000);
    await InstanaAgent.reportEvent(
        name: 'advancedCustomEvent',
        options: EventOptions()
          ..viewName = 'customViewName'
          ..startTime = DateTime.now().millisecondsSinceEpoch
          ..duration = 3 * 1000
          ..meta = {
            'customKey1': 'customValue1',
            'customKey2': 'customValue2'
          });
    await InstanaAgent.startCapture(
            url: 'https://example.com/failure', method: 'GET')
        .then((marker) => marker
          ..responseStatusCode = 500
          ..responseSizeBody = 1000
          ..responseSizeBodyDecoded = 2400
          ..errorMessage = 'Download of album failed'
          ..finish());
    await InstanaAgent.startCapture(
            url: 'https://example.com/cancel', method: 'POST')
        .then((marker) => marker.cancel());
  }

  Future<Album> fetchAlbum() async {
    final InstrumentedHttpClient httpClient =
        InstrumentedHttpClient(http.Client());

    Random random = new Random();
    var id = random.nextInt(100);
    var uid = random.nextInt(1000);
    var url = 'https://jsonplaceholder.typicode.com/albums/$id?uid=$uid';
    final http.Request request = http.Request("GET", Uri.parse(url));

    final response = await httpClient.send(request);
    if (response.statusCode == 200) {
      var responseBody = await response.stream.bytesToString();
      return Album.fromJson(jsonDecode(responseBody));
    } else {
      throw Exception('Failed to load album');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Column(
            children: <Widget>[
              ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(8.0),
                    textStyle: const TextStyle(fontSize: 16, color: Colors.blue),
                  ),
                  onPressed: () {
                    this.setState(() {
                      futureAlbum = fetchAlbum();
                    });
                  },
                  child: Text("Reload")),
              FutureBuilder<Album>(
                future: futureAlbum,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Text("Title: " +
                        snapshot.data!.title +
                        "\nID: " +
                        snapshot.data!.id.toString());
                  } else if (snapshot.hasError) {
                    return Text("${snapshot.error}");
                  } else {
                    return Text("Loading...");
                  }
                },
              )
            ],
          ),
        ),
      ),
    );
  }
}

class Album {
  final int userId;
  final int id;
  final String title;

  Album({required this.userId, required this.id, required this.title});

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      userId: json['userId'],
      id: json['id'],
      title: json['title'],
    );
  }
}
