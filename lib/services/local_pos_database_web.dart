import 'package:sembast_web/sembast_web.dart';

Future<Database> openLocalPosDatabase() =>
    databaseFactoryWeb.openDatabase('shoppad_pos');
