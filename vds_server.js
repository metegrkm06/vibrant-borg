const express = require('express');
const multer = require('multer');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const SECRET_TOKEN = 'my_super_secret_password_123'; // CHANGE THIS PASSWORD!

const MEDIA_DIR = path.join(__dirname, 'videos');

// Ensure media directory exists
if (!fs.existsSync(MEDIA_DIR)) {
    fs.mkdirSync(MEDIA_DIR, { recursive: true });
}

// Authentication Middleware
const authenticate = (req, res, next) => {
    const token = req.headers['x-secret-token'];
    if (token === SECRET_TOKEN) {
        next();
    } else {
        res.status(401).json({ error: 'Unauthorized: Invalid Secret Token' });
    }
};

// Setup Multer for file uploads
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, MEDIA_DIR);
    },
    filename: (req, file, cb) => {
        // Keep original filename but prevent overwrites
        const ext = path.extname(file.originalname);
        const name = path.basename(file.originalname, ext);
        cb(null, `${name}_${Date.now()}${ext}`);
    }
});
const upload = multer({ storage: storage });

// Function to recursively get all files
function getAllFiles(dirPath, arrayOfFiles) {
    const files = fs.readdirSync(dirPath);
    
    arrayOfFiles = arrayOfFiles || [];
    
    files.forEach(function(file) {
        if (fs.statSync(path.join(dirPath, file)).isDirectory()) {
            arrayOfFiles = getAllFiles(path.join(dirPath, file), arrayOfFiles);
        } else {
            arrayOfFiles.push(path.join(dirPath, file));
        }
    });
    
    return arrayOfFiles;
}

const videoExts = ['.mp4', '.mov', '.m4v'];
const imageExts = ['.jpg', '.jpeg', '.png', '.heic', '.webp'];
const gifExts = ['.gif'];
const allMediaExts = [...videoExts, ...imageExts, ...gifExts];

// 1. Get list of videos only (legacy endpoint)
app.get('/videos', authenticate, (req, res) => {
    try {
        const allFiles = getAllFiles(MEDIA_DIR);
        const videoFiles = allFiles.filter(f => videoExts.includes(path.extname(f).toLowerCase()));
        
        const fileData = videoFiles.map(filePath => {
            const stats = fs.statSync(filePath);
            const relativePath = path.relative(MEDIA_DIR, filePath).replace(/\\/g, '/');
            return {
                filename: relativePath,
                sizeBytes: stats.size,
                createdAt: stats.birthtime
            };
        });
        
        res.json({ videos: fileData });
    } catch (err) {
        res.status(500).json({ error: 'Failed to read directory' });
    }
});

// 1b. Get ALL media (videos, images, gifs)
app.get('/media', authenticate, (req, res) => {
    try {
        const allFiles = getAllFiles(MEDIA_DIR);
        
        const categorize = (exts) => allFiles
            .filter(f => exts.includes(path.extname(f).toLowerCase()))
            .map(filePath => {
                const stats = fs.statSync(filePath);
                const relativePath = path.relative(MEDIA_DIR, filePath).replace(/\\/g, '/');
                return { filename: relativePath, sizeBytes: stats.size, createdAt: stats.birthtime };
            });
        
        res.json({
            videos: categorize(videoExts),
            images: categorize(imageExts),
            gifs: categorize(gifExts)
        });
    } catch (err) {
        res.status(500).json({ error: 'Failed to read directory' });
    }
});

// 2. Download/Stream a file
app.get('/download', authenticate, (req, res) => {
    const relativePath = req.query.file;
    if (!relativePath) {
        return res.status(400).json({ error: 'Missing file parameter' });
    }
    const filePath = path.join(MEDIA_DIR, relativePath);
    
    if (filePath.startsWith(MEDIA_DIR) && fs.existsSync(filePath)) {
        res.sendFile(filePath);
    } else {
        res.status(404).json({ error: 'File not found' });
    }
});

// 3. Upload single file
app.post('/upload', authenticate, upload.single('video'), (req, res) => {
    if (!req.file) {
        return res.status(400).json({ error: 'No file provided' });
    }
    res.json({ message: 'Upload successful', filename: req.file.filename });
});

// 4. Bulk upload (multiple files at once)
app.post('/upload-bulk', authenticate, upload.array('files', 50), (req, res) => {
    if (!req.files || req.files.length === 0) {
        return res.status(400).json({ error: 'No files provided' });
    }
    const uploaded = req.files.map(f => f.filename);
    res.json({ message: `${uploaded.length} files uploaded`, filenames: uploaded });
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`========================================`);
    console.log(`🗂️  VDS Media Server Running!`);
    console.log(`Port: ${PORT}`);
    console.log(`Secret Token: ${SECRET_TOKEN}`);
    console.log(`Saving media to: ${MEDIA_DIR}`);
    console.log(`========================================`);
});
