"""Shared publication inventory tests; no network or normal application build."""
from copy import deepcopy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('content_publication',ROOT/'Scripts/content_publication.py')
publication=importlib.util.module_from_spec(spec);spec.loader.exec_module(publication)


def fixture(repo):
    document={'schemaVersion':1,'format':'statsdirect-published-content-v1','publisher':'StatsDirectHelpEditor',
              'publicationId':'12345678-1234-4234-8234-123456789abc','publishedAtUtc':'2026-11-04T16:01:02.1234567+00:00',
              'producer':{'version':'1.0.0','sourceCommit':'a'*40},'helpSourceSha256':'b'*64,'tutorSourceSha256':'c'*64,'artifacts':{}}
    inventories={}
    for name,prefix in publication.ARTIFACT_PATHS.items():
        inventory={}
        for file in sorted(publication.REQUIRED_FILES[name]):
            data=(name+'/'+file+'\n').encode()
            path=repo/prefix/file;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
            inventory[file]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
        item={'path':prefix,'fileCount':len(inventory),'files':[{'path':name,**meta}for name,meta in inventory.items()]}
        if name=='tutor':item.update(lessonCount=1,questionCount=1,trackCount=1,bankVersion='fixture-v1',reviewProofBinding='authoring-source-before-generated-sync-v1')
        else:item.update(topicCount=1,searchDocumentCount=1)
        if name=='desktopHelp':item.update(contextCount=1)
        document['artifacts'][name]=item;inventories[name]=inventory
    return document,inventories


def commit(repo,document):
    path=repo/publication.MANIFEST_PATH;path.parent.mkdir(parents=True,exist_ok=True)
    raw=json.dumps(document,indent=2).encode();path.write_bytes(raw)
    subprocess.run(['git','-C',str(repo),'add','.'],check=True)
    subprocess.run(['git','-C',str(repo),'-c','user.name=Content fixture','-c','user.email=fixture@example.invalid','-c','commit.gpgsign=false','commit','-qm','Published snapshot'],check=True)
    return subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip(),raw


class ContentPublicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory(prefix='statsdirect-publication-check-');self.addCleanup(self.temporary.cleanup)
        self.repo=Path(self.temporary.name)
        subprocess.run(['git','init','-q',str(self.repo)],check=True)
        self.document,self.inventories=fixture(self.repo)

    def test_binds_all_three_git_artifacts_and_retains_exact_root_bytes(self):
        revision,raw=commit(self.repo,self.document)
        proof=publication.verify_git_publication(self.repo,revision,raw)
        self.assertTrue(proof['complete']);self.assertEqual(set(proof['artifacts']),set(publication.ARTIFACT_PATHS))
        result=publication.validate_publication(raw,'desktopHelp',self.inventories['desktopHelp'])
        self.assertEqual(result['publicationManifestText'].encode(),raw)
        self.assertEqual(result['publicationManifestSHA256'],hashlib.sha256(raw).hexdigest())
        self.assertEqual(result['publicationTutorReviewProofBinding'],'authoring-source-before-generated-sync-v1')

    def test_other_artifact_tampering_blocks_help_even_when_help_itself_matches(self):
        revision,raw=commit(self.repo,self.document)
        (self.repo/'Published/Tutor/questions.json').write_text('tampered after inventory')
        changed,_=commit(self.repo,self.document)
        with self.assertRaisesRegex(publication.InvalidPublication,'bytes/hash'):
            publication.verify_git_publication(self.repo,changed,raw)
        self.assertTrue(publication.verify_git_publication(self.repo,revision,raw)['complete'])

    def test_partial_extra_unsafe_and_symlink_content_fail_closed(self):
        _,raw=commit(self.repo,self.document)
        file=self.repo/'Docs/help-viewer.js';original=file.read_bytes();file.unlink()
        revision,_=commit(self.repo,self.document)
        with self.assertRaises(publication.InvalidPublication):publication.verify_git_publication(self.repo,revision,raw)
        file.write_bytes(original)
        extra=self.repo/'Published/unrecorded.json';extra.write_text('{}')
        revision,_=commit(self.repo,self.document)
        with self.assertRaises(publication.InvalidPublication):publication.verify_git_publication(self.repo,revision,raw)
        extra.unlink();file.unlink();file.symlink_to('help-viewer.css')
        revision,_=commit(self.repo,self.document)
        with self.assertRaisesRegex(publication.InvalidPublication,'links/submodules'):
            publication.verify_git_publication(self.repo,revision,raw)

    def test_pending_marker_and_changed_root_blob_are_not_certified(self):
        _,raw=commit(self.repo,self.document)
        (self.repo/'.statsdirect-content.publishing.json').write_text('{}')
        revision,_=commit(self.repo,self.document)
        with self.assertRaisesRegex(publication.InvalidPublication,'marker'):
            publication.verify_git_publication(self.repo,revision,raw)
        (self.repo/'.statsdirect-content.publishing.json').unlink()
        changed=deepcopy(self.document);changed['producer']['version']='1.0.1'
        revision,_=commit(self.repo,changed)
        with self.assertRaisesRegex(publication.InvalidPublication,'root manifest'):
            publication.verify_git_publication(self.repo,revision,raw)

    def test_root_schema_paths_counts_review_binding_and_duplicate_json_rejected(self):
        mutations=[lambda d:d.update(schemaVersion=2),lambda d:d.update(publicationId=d['publicationId'].upper()),
                   lambda d:d['artifacts']['tutor'].pop('trackCount'),lambda d:d['artifacts']['tutor'].update(reviewProofBinding='unknown'),
                   lambda d:d['artifacts']['website'].update(path='../Docs'),lambda d:d['artifacts']['desktopHelp'].update(fileCount=99),
                   lambda d:d['artifacts']['website']['files'][0].update(path='../escape'),lambda d:d['artifacts']['tutor']['files'][0].update(bytes=True),
                   lambda d:d['artifacts']['website']['files'][0].update(path='.statsdirect-desktop-help.publishing.json'),
                   lambda d:d['artifacts']['tutor']['files'][0].update(path='.AuthoredTutor.publishing')]
        for mutate in mutations:
            d=deepcopy(self.document);mutate(d)
            with self.assertRaises(publication.InvalidPublication):publication.validate_publication(json.dumps(d).encode(),'desktopHelp',self.inventories['desktopHelp'])
        raw=json.dumps(self.document).encode().replace(b'"schemaVersion": 1',b'"schemaVersion": 1, "schemaVersion": 1')
        with self.assertRaisesRegex(publication.InvalidPublication,'Duplicate'):
            publication.validate_publication(raw,'desktopHelp',self.inventories['desktopHelp'])

    def test_selected_offline_bytes_and_inventory_are_exact(self):
        raw=json.dumps(self.document).encode()
        changed=deepcopy(self.inventories['tutor']);changed['questions.json']['sha256']='0'*64
        with self.assertRaisesRegex(publication.InvalidPublication,'Consumed tutor'):
            publication.validate_publication(raw,'tutor',changed)
        d=deepcopy(self.document);d['artifacts']['website']['files'].pop();d['artifacts']['website']['fileCount']-=1
        with self.assertRaisesRegex(publication.InvalidPublication,'required files'):
            publication.validate_publication(json.dumps(d).encode(),'tutor',self.inventories['tutor'])


if __name__=='__main__':unittest.main()
