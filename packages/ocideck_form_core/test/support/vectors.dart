import 'dart:convert';
import 'dart:io';

/// The shared vector file (FORM_INTAKE.md §4.7, §17). One file, read by every
/// test that needs a counter or a parser to agree with the others.
Map<String, dynamic> loadVectors() =>
    jsonDecode(File('test/fixtures/form_vectors.json').readAsStringSync())
        as Map<String, dynamic>;

/// A section of the vector file as a list of objects.
List<Map<String, dynamic>> vectorSection(String name) =>
    (loadVectors()[name] as List).cast<Map<String, dynamic>>();
