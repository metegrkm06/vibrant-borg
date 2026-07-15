const express = require('express');
const multer = require('multer');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const SECRET_TOKEN = 'my_super_secret_password_123'; // CHANGE THIS PASSWORD!

const VIDEOS_DIR = path.join(__dirname, 'videos');

// Ensure videos directory exists
if (!fs.existsSync(VIDEOS_DIR)) {
    fs.mkdirSync(VIDEOS_DIR, { recursive: true });
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
        cb(null, VIDEOS_DIR);
    },
    filename: (req, file, cb) => {
        // Keep original filename but prevent overwrites
        const ext = path.extname(file.originalname);
        const name = path.basename(file.originalname, ext);
        cb(null, `${name}_${Date.now()}${ext}`);
    }
});
const upload = multer({ storage: storage });

// 1. Get list of videos
app.get('/videos', authenticate, (req, res) => {
    fs.readdir(VIDEOS_DIR, (err, files) => {
        if (err) return res.status(500).json({ error: 'Failed to read directory' });
        
        const videoFiles = files.filter(f => f.endsWith('.mp4') || f.endsWith('.mov') || f.endsWith('.m4v'));
        
        const fileData = videoFiles.map(file => {
            const stats = fs.statSync(path.join(VIDEOS_DIR, file));
            return {
                filename: file,
                sizeBytes: stats.size,
                createdAt: stats.birthtime
            };
        });
        
        res.json({ videos: fileData });
    });
});

// 2. Download/Stream a video
app.get('/download/:filename', authenticate, (req, res) => {
    const filePath = path.join(VIDEOS_DIR, req.params.filename);
    if (fs.existsSync(filePath)) {
        res.sendFile(filePath);
    } else {
        res.status(404).json({ error: 'File not found' });
    }
});

// 3. Upload a video
app.post('/upload', authenticate, upload.single('video'), (req, res) => {
    if (!req.file) {
        return res.status(400).json({ error: 'No video file provided' });
    }
    res.json({ message: 'Upload successful', filename: req.file.filename });
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`========================================`);
    console.log(`🎥 VDS Video Server Running!`);
    console.log(`Port: ${PORT}`);
    console.log(`Secret Token: ${SECRET_TOKEN}`);
    console.log(`Saving videos to: ${VIDEOS_DIR}`);
    console.log(`========================================`);
});
