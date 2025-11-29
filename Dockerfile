# Step 1: Use Node image
FROM node:22

# Step 2: Create app directory
WORKDIR /app

# Step 3: Copy package files
COPY package*.json ./

# Step 4: Install dependencies
RUN npm install

# Step 5: Copy project files
COPY . .

# Step 6: Build the NestJS app
RUN npm run build

# Step 7: Start the app
CMD ["node", "dist/main.js"]
