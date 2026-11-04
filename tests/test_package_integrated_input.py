import importlib.util,pathlib,struct,unittest
spec=importlib.util.spec_from_file_location('package',pathlib.Path(__file__).parents[1]/'tools/package_integrated_input.py')
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
def image(padding=True):
    b=bytearray(1024)
    struct.pack_into('<8I',b,0,0xfeedfacf,0x100000c,0,2,1,152,0,0)
    struct.pack_into('<II16sQQQQiiII',b,32,25,152,b'__TEXT',0x100000000,4096,0,1024,7,5,1,0)
    struct.pack_into('<16s16sQQIIIIIIII',b,104,b'__text',b'__TEXT',0x100000200,64,512 if padding else 184,2,0,0,0,0,0,0)
    b[512:576]=b'X'*64
    return bytes(b)
class PackageTests(unittest.TestCase):
    def test_load_command_preserves_code_and_existing_commands(self):
        original=image();out=mod.add_dependency(original)
        self.assertEqual(out[512:],original[512:]);self.assertEqual(out[32:184],original[32:184]);self.assertEqual(struct.unpack_from('<I',out,16)[0],2)
        self.assertIn(mod.DEPENDENCY.encode(),out[:512])
    def test_rejects_duplicate(self):
        with self.assertRaises(ValueError):mod.add_dependency(mod.add_dependency(image()))
    def test_rejects_no_padding(self):
        with self.assertRaises(ValueError):mod.add_dependency(image(False))
    def test_rejects_bad_cpu(self):
        b=bytearray(image());struct.pack_into('<I',b,4,7)
        with self.assertRaises(ValueError):mod.add_dependency(bytes(b))
    def test_rejects_truncated_command(self):
        b=bytearray(image());struct.pack_into('<I',b,36,8192)
        with self.assertRaises(ValueError):mod.add_dependency(bytes(b))
    def test_rejects_signature(self):
        b=bytearray(image());struct.pack_into('<II',b,184,29,16);struct.pack_into('<II',b,16,2,168)
        with self.assertRaises(ValueError):mod.add_dependency(bytes(b))
if __name__=='__main__':unittest.main()
