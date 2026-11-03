"""Generate AltStore-compatible catalog from the verified IPA, without credentials."""
import base64,json,os,plistlib,subprocess,zipfile
from pathlib import Path
repo=os.environ['REPO']
def gh(*args):
 p=subprocess.run(['gh',*args],capture_output=True,text=True)
 if p.returncode: raise RuntimeError(p.stderr)
 return p.stdout
release=json.loads(gh('release','view','engine-trace-v4','--repo',repo,'--json','assets,url'))
asset=next(a for a in release['assets'] if a['name'].endswith('.ipa'))
ipa=Path('output/BOZ-Modern-iOS-unsigned.ipa')
with zipfile.ZipFile(ipa) as z:
 info=plistlib.loads(z.read('Payload/blackops.app/Info.plist'))
 icon=z.read('Payload/blackops.app/Icon@2x.png')
raw='https://raw.githubusercontent.com/'+repo+'/main/'
version={'version':info['CFBundleShortVersionString'],'buildNumber':info['CFBundleVersion'],'date':asset['updatedAt'],'downloadURL':asset['url'],'size':asset['size'],'minOSVersion':info['MinimumOSVersion'],'localizedDescription':'Experimental unsigned compatibility build with startup diagnostics. Gameplay is not yet verified.'}
source={'name':'Chris — BOZ for Strata','identifier':'dev.chris.boz.strata','subtitle':'Unsigned BOZ compatibility builds','website':'https://github.com/'+repo,'iconURL':raw+'source-icon.png','apps':[{'name':info['CFBundleDisplayName'],'bundleIdentifier':info['CFBundleIdentifier'],'developerName':'Activision / community compatibility patches','localizedDescription':version['localizedDescription'],'iconURL':raw+'source-icon.png','versions':[version],'version':version['version'],'versionDate':version['date'],'downloadURL':version['downloadURL'],'size':version['size']}],'news':[]}
for path,data in [('strata-source.json',json.dumps(source,indent=2).encode()),('source-icon.png',icon)]:
 endpoint='repos/'+repo+'/contents/'+path
 old=subprocess.run(['gh','api',endpoint],capture_output=True,text=True)
 body={'message':'Update Strata catalog from verified build','content':base64.b64encode(data).decode()}
 if old.returncode==0:body['sha']=json.loads(old.stdout)['sha']
 Path('source-request.json').write_text(json.dumps(body))
 gh('api','--method','PUT',endpoint,'--input','source-request.json')
print('Generated catalog matching actual IPA metadata. Private GitHub hosting requires authentication.')
