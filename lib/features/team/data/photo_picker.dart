import 'package:image_picker/image_picker.dart';

/// Chọn ảnh từ thư viện máy. Trả về đường dẫn file tạm, hoặc `null` nếu bấm hủy.
abstract interface class PhotoPicker {
  Future<String?> pickFromGallery();
}

class ImagePickerPhotoPicker implements PhotoPicker {
  ImagePickerPhotoPicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> pickFromGallery() async {
    // Chỉ thư viện (chưa dùng camera). Nén vừa phải: cạnh dài ≤ 1024 px, JPEG 85%.
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    return file?.path;
  }
}
