define(["require", "exports", "N/encode", "N/file", "N/query", "N/record"], function (require, exports, encode, file, query, record) {
    "use strict";
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.deleteFile = exports.editFile = exports.createFile = exports.listFolder = exports.resolveFileId = exports.downloadFile = exports.describeFile = exports.resolveFolder = exports.decodeUpload = exports.deriveFileType = exports.TEXT_FILE_TYPES = exports.EXTENSION_TYPE_MAP = exports.MAX_CONTENT_BYTES = exports.ValidationError = void 0;
    // ============ Canonical module interfaces (binding) ============
    class ValidationError extends Error {
    }
    exports.ValidationError = ValidationError;
    exports.MAX_CONTENT_BYTES = 10_485_760; // NetSuite's getContents()/save ceiling
    exports.EXTENSION_TYPE_MAP = {
        bmp: 'BMPIMAGE', cfg: 'CONFIG', conf: 'CONFIG', css: 'STYLESHEET', csv: 'CSV',
        doc: 'WORD', docx: 'WORD', eml: 'MESSAGERFC', ftl: 'FREEMARKER', gif: 'GIFIMAGE',
        gz: 'GZIP', htm: 'HTMLDOC', html: 'HTMLDOC', ico: 'ICON', jpeg: 'JPGIMAGE',
        jpg: 'JPGIMAGE', js: 'JAVASCRIPT', json: 'JSON', md: 'PLAINTEXT', mp3: 'MP3',
        pdf: 'PDF', png: 'PNGIMAGE', ppt: 'POWERPOINT', pptx: 'POWERPOINT', scss: 'SCSS',
        svg: 'SVG', tar: 'TAR', tif: 'TIFFIMAGE', tiff: 'TIFFIMAGE', txt: 'PLAINTEXT',
        xls: 'EXCEL', xlsx: 'EXCEL', xml: 'XMLDOC', xsd: 'XSD', zip: 'ZIP',
    };
    // ============ Task 1: File types & upload decoding ============
    // Runtime values of file.Type are the member names, so the module stores/compares plain strings
    // (testable under mocked N/file) and converts via fileTypeEnum() only at file.create() time.
    const KNOWN_FILE_TYPES = new Set([
        'APPCACHE', 'AUTOCAD', 'BMPIMAGE', 'CERTIFICATE', 'CONFIG', 'CSV', 'EXCEL', 'FLASH',
        'FREEMARKER', 'GIFIMAGE', 'GZIP', 'HTMLDOC', 'ICON', 'JAVASCRIPT', 'JPGIMAGE', 'JSON',
        'MESSAGERFC', 'MP3', 'MPEGMOVIE', 'MSPROJECT', 'PDF', 'PJPGIMAGE', 'PLAINTEXT', 'PNGIMAGE',
        'POSTSCRIPT', 'POWERPOINT', 'QUICKTIME', 'RTF', 'SCSS', 'SMS', 'STYLESHEET', 'SVG', 'TAR',
        'TIFFIMAGE', 'VISIO', 'WEBAPPPAGE', 'WEBAPPSCRIPT', 'WORD', 'XMLDOC', 'XSD', 'ZIP',
    ]);
    exports.TEXT_FILE_TYPES = new Set([
        'CONFIG', 'CSV', 'FREEMARKER', 'HTMLDOC', 'JAVASCRIPT', 'JSON', 'MESSAGERFC', 'PLAINTEXT',
        'SCSS', 'STYLESHEET', 'SVG', 'WEBAPPPAGE', 'WEBAPPSCRIPT', 'XMLDOC', 'XSD',
    ]);
    const deriveFileType = (name, explicit) => {
        if (explicit !== undefined) {
            if (typeof explicit !== 'string' || !KNOWN_FILE_TYPES.has(explicit)) {
                throw new ValidationError(`fileType must be one of ${[...KNOWN_FILE_TYPES].sort().join(', ')}`);
            }
            return explicit;
        }
        const extension = name.includes('.') ? name.slice(name.lastIndexOf('.') + 1).toLowerCase() : '';
        const mapped = exports.EXTENSION_TYPE_MAP[extension];
        if (!mapped) {
            throw new ValidationError(`cannot derive a fileType from "${name}" — pass an explicit fileType`);
        }
        return mapped;
    };
    exports.deriveFileType = deriveFileType;
    const BASE64_SHAPE = /^[A-Za-z0-9+/]*={0,2}$/;
    // Returns the string file.create() wants: real text for text types, base64 for binary types.
    const decodeUpload = (contents, contentsEncoding, fileType) => {
        if (typeof contents !== 'string') {
            throw new ValidationError('contents is required and must be a string (empty string is allowed)');
        }
        const encodingName = normalizeContentsEncoding(contentsEncoding);
        const isText = exports.TEXT_FILE_TYPES.has(fileType);
        if (encodingName === 'utf8') {
            if (!isText) {
                throw new ValidationError(`${fileType} is a binary file type — send contents as base64 with "contentsEncoding": "base64"`);
            }
            assertUnderCap(utf8ByteLength(contents));
            return contents;
        }
        const stripped = contents.replace(/\s/g, '');
        if (stripped.length % 4 !== 0 || !BASE64_SHAPE.test(stripped)) {
            throw new ValidationError('contents is not valid base64');
        }
        const padding = stripped.endsWith('==') ? 2 : stripped.endsWith('=') ? 1 : 0;
        assertUnderCap((stripped.length / 4) * 3 - padding);
        if (!isText)
            return stripped;
        return encode.convert({
            string: stripped,
            inputEncoding: encode.Encoding.BASE_64,
            outputEncoding: encode.Encoding.UTF_8,
        });
    };
    exports.decodeUpload = decodeUpload;
    const normalizeContentsEncoding = (contentsEncoding) => {
        if (contentsEncoding === undefined || contentsEncoding === 'utf8')
            return 'utf8';
        if (contentsEncoding === 'base64')
            return 'base64';
        throw new ValidationError(`contentsEncoding must be "utf8" or "base64", got ${JSON.stringify(contentsEncoding)}`);
    };
    const assertUnderCap = (byteLength) => {
        if (byteLength > exports.MAX_CONTENT_BYTES) {
            throw new ValidationError(`contents is ${byteLength} bytes decoded — the cap is ${exports.MAX_CONTENT_BYTES} (10MB)`);
        }
    };
    const utf8ByteLength = (value) => {
        let bytes = 0;
        for (const character of value) {
            const codePoint = character.codePointAt(0);
            bytes += codePoint <= 0x7f ? 1 : codePoint <= 0x7ff ? 2 : codePoint <= 0xffff ? 3 : 4;
        }
        return bytes;
    };
    // Resolves a folder target — numeric internal id (number or numeric string) or absolute path —
    // to id + canonical path. autoCreate builds missing trailing segments; only create/move pass true.
    const resolveFolder = (target, autoCreate) => {
        if (typeof target === 'number' || (typeof target === 'string' && /^\d+$/.test(target))) {
            const folderId = Number(target);
            return { id: folderId, path: folderPathById(folderId) };
        }
        if (typeof target !== 'string') {
            throw new ValidationError('folder must be a numeric internal id or an absolute path like /SuiteScripts/CreativePlanning');
        }
        const segments = splitFolderPath(target);
        let parentId = null;
        const resolvedSegments = [];
        for (const segment of segments) {
            const matches = childFolders(parentId, segment);
            if (matches.length > 1) {
                throw new ValidationError(`folder name "${segment}" under /${resolvedSegments.join('/')} matches multiple folders ` +
                    `(ids ${matches.map((match) => match.id).join(', ')}) — use the numeric id instead`);
            }
            if (matches.length === 1) {
                parentId = matches[0].id;
                resolvedSegments.push(matches[0].name);
                continue;
            }
            if (!autoCreate) {
                throw new ValidationError(`folder not found: /${[...resolvedSegments, segment].join('/')}`);
            }
            parentId = createFolder(segment, parentId);
            resolvedSegments.push(segment);
        }
        return { id: parentId, path: `/${resolvedSegments.join('/')}` };
    };
    exports.resolveFolder = resolveFolder;
    const splitFolderPath = (path) => {
        if (!path.startsWith('/')) {
            throw new ValidationError(`a File Cabinet path must be absolute (start with /), got ${JSON.stringify(path)}`);
        }
        const segments = path.split('/').slice(1);
        if (segments.length > 0 && segments[segments.length - 1] === '')
            segments.pop(); // tolerate one trailing slash
        if (segments.some((segment) => segment.trim() === '')) {
            throw new ValidationError(`path has an empty segment: ${JSON.stringify(path)}`);
        }
        return segments;
    };
    const childFolders = (parentId, name) => query
        .runSuiteQL({
        query: /* sql */ `
        SELECT id, name
          FROM mediaitemfolder
         WHERE LOWER(name) = LOWER(?)
           AND ${parentId === null ? 'parent IS NULL' : 'parent = ?'}`,
        params: parentId === null ? [name] : [name, parentId],
    })
        .asMappedResults();
    const createFolder = (name, parentId) => {
        const folder = record.create({ type: 'folder' });
        folder.setValue({ fieldId: 'name', value: name });
        if (parentId !== null)
            folder.setValue({ fieldId: 'parent', value: parentId });
        return folder.save();
    };
    const MAX_FOLDER_DEPTH = 50; // cycle guard for the upward walk
    const folderPathById = (folderId) => {
        const segments = [];
        let currentId = folderId;
        for (let depth = 0; currentId !== null && depth < MAX_FOLDER_DEPTH; depth += 1) {
            const rows = query
                .runSuiteQL({
                query: /* sql */ `SELECT id, name, parent FROM mediaitemfolder WHERE id = ?`,
                params: [currentId],
            })
                .asMappedResults();
            if (rows.length === 0)
                throw new ValidationError(`folder ${folderId} does not exist`);
            segments.unshift(rows[0].name);
            currentId = rows[0].parent ?? null;
        }
        if (currentId !== null) {
            throw new Error(`folder ${folderId} parent chain exceeds ${MAX_FOLDER_DEPTH} levels — cycle suspected`);
        }
        return `/${segments.join('/')}`;
    };
    const joinPath = (folderPath, name) => folderPath === '/' ? `/${name}` : `${folderPath}/${name}`;
    const describeFile = (fileId) => serializeLoaded(loadFile(fileId));
    exports.describeFile = describeFile;
    const downloadFile = (fileId) => {
        const loaded = loadFile(fileId);
        if (loaded.size > exports.MAX_CONTENT_BYTES) {
            throw new ValidationError(`file is ${loaded.size} bytes — NetSuite caps getContents() at ${exports.MAX_CONTENT_BYTES}; fetch it via its url in the UI instead`);
        }
        const description = serializeLoaded(loaded);
        return {
            ...description,
            contents: loaded.getContents(),
            contentsEncoding: exports.TEXT_FILE_TYPES.has(description.fileType) ? 'utf8' : 'base64',
        };
    };
    exports.downloadFile = downloadFile;
    const resolveFileId = (idParam, pathParam) => {
        const hasId = idParam !== undefined;
        const hasPath = pathParam !== undefined;
        if (hasId === hasPath) {
            throw new ValidationError('pass exactly one of id (numeric internal id) or path (absolute File Cabinet path)');
        }
        if (hasId) {
            if (typeof idParam !== 'number' && !(typeof idParam === 'string' && /^\d+$/.test(idParam))) {
                throw new ValidationError(`id must be a numeric internal id, got ${JSON.stringify(idParam)}`);
            }
            return Number(idParam);
        }
        if (typeof pathParam !== 'string')
            throw new ValidationError('path must be a string');
        const segments = splitFolderPath(pathParam);
        if (segments.length === 0)
            throw new ValidationError('path points at the File Cabinet root, not a file');
        const name = segments[segments.length - 1];
        const parent = (0, exports.resolveFolder)(segments.length === 1 ? '/' : `/${segments.slice(0, -1).join('/')}`, false);
        const fileId = findFileIdInFolder(parent.id, name);
        if (fileId !== null)
            return fileId;
        if (childFolders(parent.id, name).length > 0) {
            throw new ValidationError(`${pathParam} is a folder — file operations need a file; use folder= to list it`);
        }
        throw new ValidationError(`file not found: ${pathParam}`);
    };
    exports.resolveFileId = resolveFileId;
    // An id N/file can't load is a caller mistake (typo, wrong environment, deleted file), so it maps
    // to ValidationError — same contract as the saved-search RESTlet's loadSearch.
    const loadFile = (fileId) => {
        try {
            return file.load({ id: fileId });
        }
        catch (err) {
            throw new ValidationError(err.message || String(err));
        }
    };
    const serializeLoaded = (loaded) => {
        const path = loaded.path.startsWith('/') ? loaded.path : `/${loaded.path}`;
        const dates = fileDates(Number(loaded.id));
        return {
            id: Number(loaded.id),
            name: loaded.name,
            path,
            folder: {
                id: loaded.folder === undefined || loaded.folder === null ? null : Number(loaded.folder),
                path: path.slice(0, path.length - loaded.name.length - 1) || '/',
            },
            fileType: String(loaded.fileType),
            size: Number(loaded.size),
            url: loaded.url ?? null,
            description: loaded.description || null,
            encoding: loaded.encoding === undefined || loaded.encoding === null ? null : String(loaded.encoding),
            isOnline: Boolean(loaded.isOnline),
            isInactive: Boolean(loaded.isInactive),
            createdDate: dates.createddate ?? null,
            lastModifiedDate: dates.lastmodifieddate ?? null,
        };
    };
    const fileDates = (fileId) => {
        const rows = query
            .runSuiteQL({
            query: /* sql */ `SELECT createddate, lastmodifieddate FROM file WHERE id = ?`,
            params: [fileId],
        })
            .asMappedResults();
        return rows[0] ?? {};
    };
    const findFileIdInFolder = (folderId, name) => {
        const rows = query
            .runSuiteQL({
            query: /* sql */ `
        SELECT id
          FROM file
         WHERE LOWER(name) = LOWER(?)
           AND ${folderId === null ? 'folder IS NULL' : 'folder = ?'}`,
            params: folderId === null ? [name] : [name, folderId],
        })
            .asMappedResults();
        if (rows.length > 1) {
            throw new ValidationError(`"${name}" matches multiple files in that folder (ids ${rows.map((row) => row.id).join(', ')}) — use id instead`);
        }
        return rows.length === 1 ? rows[0].id : null;
    };
    const listFolder = (folderParam, nameContains) => {
        const folder = (0, exports.resolveFolder)(folderParam, false);
        const subfolders = query
            .runSuiteQL({
            query: /* sql */ `
        SELECT id, name
          FROM mediaitemfolder
         WHERE ${folder.id === null ? 'parent IS NULL' : 'parent = ?'}
         ORDER BY name`,
            params: folder.id === null ? [] : [folder.id],
        })
            .asMappedResults();
        const hasNameFilter = nameContains !== undefined && nameContains !== '';
        const fileParams = folder.id === null ? [] : [folder.id];
        if (hasNameFilter)
            fileParams.push(`%${nameContains.toLowerCase()}%`);
        const files = query
            .runSuiteQL({
            query: /* sql */ `
        SELECT id, name, filesize, filetype, url, lastmodifieddate
          FROM file
         WHERE ${folder.id === null ? 'folder IS NULL' : 'folder = ?'}
           ${hasNameFilter ? 'AND LOWER(name) LIKE ?' : ''}
         ORDER BY name`,
            params: fileParams,
        })
            .asMappedResults();
        return {
            folder,
            folders: subfolders.map((row) => ({ id: row.id, name: row.name, path: joinPath(folder.path, row.name) })),
            files: files.map((row) => ({
                id: row.id,
                name: row.name,
                size: row.filesize ?? null,
                fileType: row.filetype ?? null,
                url: row.url ?? null,
                lastModifiedDate: row.lastmodifieddate ?? null,
            })),
        };
    };
    exports.listFolder = listFolder;
    // ============ Task 5: Create (upload) with overwrite guard ============
    const CREATE_KEYS = new Set(['path', 'folder', 'name', 'contents', 'contentsEncoding', 'fileType', 'description', 'isOnline', 'encoding', 'overwrite']);
    const createFile = (body) => {
        const request = asObject(body, CREATE_KEYS);
        if (request.overwrite !== undefined && typeof request.overwrite !== 'boolean') {
            throw new ValidationError('overwrite must be a boolean');
        }
        const target = resolveCreateTarget(request);
        if (target.folder.id === null) {
            throw new ValidationError('cannot create files at the File Cabinet root — target a folder');
        }
        const fileType = (0, exports.deriveFileType)(target.name, request.fileType);
        const contents = (0, exports.decodeUpload)(request.contents, request.contentsEncoding, fileType);
        const existingId = findFileIdInFolder(target.folder.id, target.name);
        if (existingId !== null && request.overwrite !== true) {
            throw new ValidationError(`file already exists at ${joinPath(target.folder.path, target.name)} (id ${existingId}) — pass "overwrite": true to replace it`);
        }
        const created = file.create({
            name: target.name,
            folder: target.folder.id,
            fileType: fileTypeEnum(fileType),
            contents,
            ...(request.description !== undefined ? { description: requireString(request.description, 'description') } : {}),
            ...(request.isOnline !== undefined ? { isOnline: requireBoolean(request.isOnline, 'isOnline') } : {}),
            ...(request.encoding !== undefined ? { encoding: encodingEnum(request.encoding) } : {}),
        });
        return (0, exports.describeFile)(created.save());
    };
    exports.createFile = createFile;
    const resolveCreateTarget = (request) => {
        const hasPath = request.path !== undefined;
        const hasFolderOrName = request.folder !== undefined || request.name !== undefined;
        if (hasPath === hasFolderOrName) {
            throw new ValidationError('target a create with either "path" or with both "folder" and "name"');
        }
        if (hasPath) {
            const segments = splitFolderPath(requireString(request.path, 'path'));
            if (segments.length === 0)
                throw new ValidationError('path must include a file name');
            return {
                name: segments[segments.length - 1],
                folder: (0, exports.resolveFolder)(segments.length === 1 ? '/' : `/${segments.slice(0, -1).join('/')}`, true),
            };
        }
        if (request.folder === undefined || request.name === undefined) {
            throw new ValidationError('target a create with either "path" or with both "folder" and "name"');
        }
        return { folder: (0, exports.resolveFolder)(request.folder, true), name: requireFileName(request.name) };
    };
    const asObject = (body, allowedKeys) => {
        const parsed = typeof body === 'string' && body !== '' ? parseJson(body) : body;
        if (parsed === null || parsed === undefined || typeof parsed !== 'object' || Array.isArray(parsed)) {
            throw new ValidationError('request body must be a JSON object');
        }
        const request = parsed;
        const unknownKeys = Object.keys(request).filter((key) => !allowedKeys.has(key));
        if (unknownKeys.length > 0) {
            throw new ValidationError(`unknown key(s): ${unknownKeys.join(', ')} — allowed keys: ${[...allowedKeys].join(', ')}`);
        }
        return request;
    };
    const parseJson = (body) => {
        try {
            return JSON.parse(body);
        }
        catch {
            throw new ValidationError('request body is not valid JSON');
        }
    };
    // ============ Task 6: Edit (patch) and delete ============
    const EDIT_KEYS = new Set(['id', 'path', 'contents', 'contentsEncoding', 'name', 'folder', 'description', 'isOnline', 'isInactive', 'fileType']);
    const EDITABLE_KEYS = ['contents', 'name', 'folder', 'description', 'isOnline', 'isInactive'];
    const editFile = (body) => {
        const request = asObject(body, EDIT_KEYS);
        const fileId = (0, exports.resolveFileId)(request.id, request.path);
        // Deliberately loaded before the "nothing to edit" check below, so a fileType-change-only body
        // (no other editable key) fails with the fileType message, not "nothing to edit" — don't reorder.
        let loaded = loadFile(fileId);
        const currentType = String(loaded.fileType);
        if (request.fileType !== undefined && request.fileType !== currentType) {
            throw new ValidationError(`fileType cannot be changed — the file's type is ${currentType}`);
        }
        if (!EDITABLE_KEYS.some((key) => request[key] !== undefined)) {
            throw new ValidationError(`nothing to edit — pass at least one of ${EDITABLE_KEYS.join(', ')}`);
        }
        if (request.contents !== undefined) {
            replaceContents(loaded, (0, exports.decodeUpload)(request.contents, request.contentsEncoding, currentType));
            loaded = loadFile(fileId);
        }
        if (applyMetadata(loaded, request))
            loaded.save();
        return (0, exports.describeFile)(fileId);
    };
    exports.editFile = editFile;
    const deleteFile = (idParam, pathParam) => {
        const fileId = (0, exports.resolveFileId)(idParam, pathParam);
        const description = (0, exports.describeFile)(fileId); // also proves the id is a real, loadable file
        file.delete({ id: fileId });
        return { deleted: true, id: description.id, path: description.path };
    };
    exports.deleteFile = deleteFile;
    // NetSuite has no in-place content setter: saving a file with the same name into the same folder
    // is the documented replace mechanism and retains the internal id. The id check makes that
    // QA-verified assumption loud if it ever breaks, instead of leaving a silent duplicate behind.
    const replaceContents = (loaded, contents) => {
        if (loaded.folder === null || loaded.folder === undefined) {
            throw new ValidationError(`${loaded.name} lives at the File Cabinet root — content replace there isn't supported (root files can't be created by this RESTlet either)`);
        }
        const replacement = file.create({
            name: loaded.name,
            folder: Number(loaded.folder),
            fileType: fileTypeEnum(String(loaded.fileType)),
            contents,
            ...(loaded.description ? { description: loaded.description } : {}),
            isOnline: Boolean(loaded.isOnline),
            isInactive: Boolean(loaded.isInactive),
            ...(loaded.encoding ? { encoding: encodingEnumFromLoaded(loaded.encoding) } : {}),
        });
        const replacedId = replacement.save();
        if (replacedId !== Number(loaded.id)) {
            throw new Error(`content replace saved as new file ${replacedId} instead of overwriting ${loaded.id} — clean up the duplicate before retrying`);
        }
    };
    const applyMetadata = (loaded, request) => {
        let changed = false;
        if (request.name !== undefined) {
            loaded.name = requireFileName(request.name);
            changed = true;
        }
        if (request.folder !== undefined) {
            const destination = (0, exports.resolveFolder)(request.folder, true);
            if (destination.id === null) {
                throw new ValidationError('cannot move a file to the File Cabinet root — target a folder');
            }
            loaded.folder = destination.id;
            changed = true;
        }
        if (request.description !== undefined) {
            loaded.description = requireString(request.description, 'description');
            changed = true;
        }
        if (request.isOnline !== undefined) {
            loaded.isOnline = requireBoolean(request.isOnline, 'isOnline');
            changed = true;
        }
        if (request.isInactive !== undefined) {
            loaded.isInactive = requireBoolean(request.isInactive, 'isInactive');
            changed = true;
        }
        return changed;
    };
    // ============ Helper functions (wired in later tasks) ============
    const fileTypeEnum = (name) => file.Type[name];
    const FILE_ENCODINGS = ['UTF_8', 'WINDOWS_1252', 'ISO_8859_1', 'GB18030', 'SHIFT_JIS', 'MAC_ROMAN', 'GB2312', 'BIG5'];
    const encodingEnum = (value) => {
        if (typeof value !== 'string' || !FILE_ENCODINGS.includes(value)) {
            throw new ValidationError(`encoding must be one of ${FILE_ENCODINGS.join(', ')}`);
        }
        return file.Encoding[value];
    };
    // File.encoding reads back as a charset display string, not the enum key — every value below was
    // captured live in a sandbox (2026-08-11) by creating a file with each of the 8 supported encodings and
    // describing it. MacRoman is why this is an explicit map and not a mechanical normalization:
    // "MacRoman".toUpperCase() is "MACROMAN", which is not an enum key, and the failed lookup would
    // silently reset the file to UTF-8 on content replace.
    const ENCODING_READBACK_KEYS = {
        'UTF-8': 'UTF_8',
        'windows-1252': 'WINDOWS_1252',
        'ISO-8859-1': 'ISO_8859_1',
        GB18030: 'GB18030',
        SHIFT_JIS: 'SHIFT_JIS',
        MacRoman: 'MAC_ROMAN',
        GB2312: 'GB2312',
        Big5: 'BIG5',
    };
    const encodingEnumFromLoaded = (value) => {
        const encodingKey = ENCODING_READBACK_KEYS[value];
        if (encodingKey === undefined) {
            // Plain Error, not ValidationError: an unmapped readback is a platform surprise, and dropping
            // it would silently re-encode the file — the failure this map exists to prevent.
            throw new Error(`unrecognized encoding "${value}" on the existing file — content replace aborted to avoid re-encoding it`);
        }
        return file.Encoding[encodingKey];
    };
    const requireFileName = (value) => {
        const name = requireString(value, 'name');
        if (name.trim() === '' || name.includes('/')) {
            throw new ValidationError('name must be a plain file name with no slashes');
        }
        return name;
    };
    const requireString = (value, fieldName) => {
        if (typeof value !== 'string')
            throw new ValidationError(`${fieldName} must be a string`);
        return value;
    };
    const requireBoolean = (value, fieldName) => {
        if (typeof value !== 'boolean')
            throw new ValidationError(`${fieldName} must be a boolean`);
        return value;
    };
});
