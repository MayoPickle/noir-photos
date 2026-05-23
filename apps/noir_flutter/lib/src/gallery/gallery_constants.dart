const noirDefaultLibraryName = 'Library';
const noirDefaultLibraryType = 'library';
const noirAlbumCollectionType = 'album';

bool isLibraryCollection(Map<String, dynamic> collection) {
  return collection['collection_type']?.toString() == noirDefaultLibraryType;
}

List<Map<String, dynamic>> libraryFirst(
    Iterable<Map<String, dynamic>> collections) {
  final libraries = <Map<String, dynamic>>[];
  final albums = <Map<String, dynamic>>[];
  for (final collection in collections) {
    if (isLibraryCollection(collection)) {
      libraries.add(collection);
    } else {
      albums.add(collection);
    }
  }
  return [...libraries, ...albums];
}
