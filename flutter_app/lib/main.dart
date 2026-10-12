import 'package:flutter/material.dart';
import 'core/config/app_config.dart';
import 'core/network/auth_service.dart';
import 'features/files/services/file_service.dart';
import 'features/auth/screens/splash_screen.dart';

void main() {
  // Services are initialised here so the backend URL is defined in one place.
  // FileService requires a JWT token; in a real flow the token comes from AuthService
  // after the user logs in. For now we pass an empty token so the app starts cleanly.
  final authService = AuthService(baseUrl: AppConfig.backendBaseUrl);
  final fileService = FileService(
    baseUrl: AppConfig.backendBaseUrl,
    jwtToken: authService.jwtToken ?? '',
  );

  runApp(MyApp(authService: authService, fileService: fileService));
}

class MyApp extends StatelessWidget {
  final AuthService authService;
  final FileService fileService; // Keeping this for now if it's injected elsewhere, though HomeScreen instantiates its own. Let's clean it up to just take authService and let HomeScreen handle the rest, or just keep passing it if needed. Actually we only need AuthService at the root.

  const MyApp({super.key, required this.authService, required this.fileService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OfflineMesh',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: SplashScreen(authService: authService),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.title,
    required this.authService,
    required this.fileService,
  });

  final String title;
  final AuthService authService;
  final FileService fileService;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
